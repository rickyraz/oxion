import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const rootDir = process.cwd();
const interfacesDir = join(rootDir, "generated", "interfaces");
const outputFile = join(rootDir, "generated", "contracts.zod.ts");

type InterfaceTypeRef = {
  kind: string;
  module?: string;
  name?: string;
  parameters?: InterfaceTypeRef[];
  elements?: InterfaceTypeRef[];
};

type InterfaceFunction = {
  parameters?: { label?: string | null; type: InterfaceTypeRef }[];
  return?: InterfaceTypeRef;
};

type InterfaceConstructor = {
  name: string;
  parameters?: { label?: string | null; type: InterfaceTypeRef }[];
};

type InterfaceType = {
  constructors?: InterfaceConstructor[];
};

type InterfaceModule = {
  types?: Record<string, InterfaceType>;
  functions?: Record<string, InterfaceFunction>;
};

type PackageInterface = {
  name: string;
  version: string;
  modules?: Record<string, InterfaceModule>;
};

type ZodMappedType = {
  name: string;
  schemaExpr: string;
};

type ZodMappedFunction = {
  name: string;
  paramsExpr: string;
  returnExpr: string;
};

type ZodMappedModule = {
  moduleName: string;
  namespace: string;
  types: ZodMappedType[];
  functions: ZodMappedFunction[];
};

type ZodMappedPackage = {
  packageName: string;
  version: string;
  modules: ZodMappedModule[];
};

function sanitizeModuleNamespace(moduleName: string): string {
  return moduleName
    .replace(/[^A-Za-z0-9_]/g, "_")
    .replace(/^[0-9]/, "_$&");
}

function asObjectKey(label: string): string {
  if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(label)) return label;
  return JSON.stringify(label);
}

function mapTypeRefToZodExpr(
  t: InterfaceTypeRef | undefined,
  currentModule: string,
  knownModules: Set<string>
): string {
  if (!t || typeof t !== "object") return "z.unknown()";

  if (t.kind === "named") {
    const moduleName = t.module ?? "";
    const name = t.name ?? "";
    const params = t.parameters ?? [];

    if (moduleName === "gleam" && name === "String") return "z.string()";
    if (moduleName === "gleam" && name === "Int") return "z.number().int()";
    if (moduleName === "gleam" && name === "Float") return "z.number()";
    if (moduleName === "gleam" && name === "Bool") return "z.boolean()";
    if (moduleName === "gleam" && name === "Nil") return "z.null()";
    if (moduleName === "gleam" && name === "BitArray") {
      return "z.instanceof(Uint8Array)";
    }
    if (moduleName === "gleam" && name === "List") {
      const item = mapTypeRefToZodExpr(params[0], currentModule, knownModules);
      return `z.array(${item})`;
    }
    if (moduleName === "gleam/option" && name === "Option") {
      const inner = mapTypeRefToZodExpr(params[0], currentModule, knownModules);
      return `${inner}.nullable()`;
    }
    if (moduleName === "gleam" && name === "Result") {
      const ok = mapTypeRefToZodExpr(params[0], currentModule, knownModules);
      const err = mapTypeRefToZodExpr(params[1], currentModule, knownModules);
      return `z.union([z.object({ tag: z.literal("Ok"), value: ${ok} }), z.object({ tag: z.literal("Error"), error: ${err} })])`;
    }
    if (moduleName === "gleam" && name === "Dict") {
      const key = mapTypeRefToZodExpr(params[0], currentModule, knownModules);
      const value = mapTypeRefToZodExpr(params[1], currentModule, knownModules);
      return `z.array(z.tuple([${key}, ${value}]))`;
    }
    if (moduleName === "gleam/dynamic" && name === "Dynamic") {
      return "z.unknown()";
    }

    if (knownModules.has(moduleName)) {
      if (moduleName === currentModule) return name;
      return `${sanitizeModuleNamespace(moduleName)}.${name}`;
    }
    return "z.unknown()";
  }

  if (t.kind === "tuple") {
    const elements = t.elements ?? [];
    return `z.tuple([${elements
      .map((e) => mapTypeRefToZodExpr(e, currentModule, knownModules))
      .join(", ")}])`;
  }

  if (t.kind === "variable") return "z.unknown()";
  if (t.kind === "fn") return "z.unknown()";
  return "z.unknown()";
}

function mapConstructorToSchemaExpr(
  cons: InterfaceConstructor,
  currentModule: string,
  knownModules: Set<string>
): string {
  const params = cons.parameters ?? [];
  const fields = params.map((p, i) => {
    const field = p.label ?? `_${i}`;
    return `${asObjectKey(field)}: ${mapTypeRefToZodExpr(p.type, currentModule, knownModules)}`;
  });
  const objectFields = [`tag: z.literal("${cons.name}")`, ...fields].join(", ");
  return `z.object({ ${objectFields} })`;
}

function mapModuleToZodModel(
  moduleName: string,
  moduleDef: InterfaceModule,
  knownModules: Set<string>
): ZodMappedModule {
  const types = Object.entries(moduleDef.types ?? {}).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  const mappedTypes: ZodMappedType[] = types.map(([typeName, typeDef]) => {
    const constructors = typeDef.constructors ?? [];
    if (constructors.length === 0) {
      return {
        name: typeName,
        schemaExpr: "z.unknown()"
      };
    }

    const unionExpr =
      constructors.length === 1
        ? mapConstructorToSchemaExpr(constructors[0], moduleName, knownModules)
        : `z.union([${constructors
            .map((c) => mapConstructorToSchemaExpr(c, moduleName, knownModules))
            .join(", ")}])`;

    return {
      name: typeName,
      schemaExpr: `z.lazy(() => ${unionExpr})`
    };
  });

  const functions = Object.entries(moduleDef.functions ?? {}).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  const mappedFunctions: ZodMappedFunction[] = functions.map(([fnName, fnDef]) => {
    const params = fnDef.parameters ?? [];
    const paramSchemas = params
      .map((p) => mapTypeRefToZodExpr(p.type, moduleName, knownModules))
      .join(", ");
    return {
      name: fnName,
      paramsExpr: `z.tuple([${paramSchemas}])`,
      returnExpr: mapTypeRefToZodExpr(fnDef.return, moduleName, knownModules)
    };
  });

  return {
    moduleName,
    namespace: sanitizeModuleNamespace(moduleName),
    types: mappedTypes,
    functions: mappedFunctions
  };
}

function renderMappedModule(model: ZodMappedModule): string {
  const lines: string[] = [];
  lines.push(`export namespace ${model.namespace} {`);

  for (const typeModel of model.types) {
    lines.push(`  export const ${typeModel.name}: z.ZodTypeAny = ${typeModel.schemaExpr};`);
    lines.push(`  export type ${typeModel.name} = z.infer<typeof ${typeModel.name}>;`);
  }

  for (const fnModel of model.functions) {
    lines.push(
      `  export const Fn_${fnModel.name}_params = ${fnModel.paramsExpr};`
    );
    lines.push(`  export const Fn_${fnModel.name}_return = ${fnModel.returnExpr};`);
  }

  lines.push("}");
  lines.push("");
  return lines.join("\n");
}

function writeIfChanged(file: string, content: string): boolean {
  let current = "";
  try {
    current = readFileSync(file, "utf8");
  } catch {
    current = "";
  }
  if (current !== content) {
    writeFileSync(file, content, "utf8");
    return true;
  }
  return false;
}

const interfaceFiles = readdirSync(interfacesDir)
  .filter((f) => f.endsWith(".interface.json"))
  .sort();
if (interfaceFiles.length === 0) {
  throw new Error(
    "No interface artifacts found in generated/interfaces. Run `pnpm run generate:contracts` first."
  );
}

const interfaces: PackageInterface[] = interfaceFiles.map((file) =>
  JSON.parse(readFileSync(join(interfacesDir, file), "utf8"))
);

const allModules = new Set<string>();
for (const iface of interfaces) {
  for (const moduleName of Object.keys(iface.modules ?? {})) {
    allModules.add(moduleName);
  }
}

const mappedPackages: ZodMappedPackage[] = interfaces.map((iface) => {
  const modules = Object.entries(iface.modules ?? {}).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  return {
    packageName: iface.name,
    version: iface.version,
    modules: modules.map(([moduleName, moduleDef]) =>
      mapModuleToZodModel(moduleName, moduleDef, allModules)
    )
  };
});

const lines: string[] = [];
lines.push("// AUTO-GENERATED ZOD SCHEMAS FROM GLEAM PACKAGE INTERFACES.");
lines.push("// Source interfaces: generated/interfaces/*.interface.json");
lines.push("// Mapping layer: interface.json -> Zod model -> TypeScript renderer");
lines.push("// Generator entrypoint: /scripts/generate-zod.ts");
lines.push('import { z } from "zod";');
lines.push("");

for (const pkg of mappedPackages) {
  lines.push(`// package: ${pkg.packageName}@${pkg.version}`);
  for (const moduleModel of pkg.modules) {
    lines.push(renderMappedModule(moduleModel));
  }
}

lines.push("export const GeneratedZodStatus = z.literal(\"gleam_source_of_truth\");");
lines.push("");

const changed = writeIfChanged(outputFile, lines.join("\n"));
if (changed) {
  console.log("Updated generated/contracts.zod.ts");
} else {
  console.log("generated/contracts.zod.ts is up to date");
}
