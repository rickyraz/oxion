import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = process.cwd();
const generatedDir = join(rootDir, "generated");
const outputFile = join(generatedDir, "contracts.generated.ts");
const interfaceDir = join(generatedDir, "interfaces");

const gleamSourcePackages = [
  {
    name: "oxion_policy",
    dir: join(rootDir, "packages", "policy")
  },
  {
    name: "oxion_interop",
    dir: join(rootDir, "packages", "interop")
  }
];

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, stdio: "inherit" });
  if (result.status !== 0) {
    throw new Error(
      `Command failed in ${cwd}: ${command} ${args.join(" ")}`
    );
  }
}

function sanitizeModuleNamespace(moduleName) {
  return moduleName
    .replace(/[^A-Za-z0-9_]/g, "_")
    .replace(/^[0-9]/, "_$&");
}

function namedTypeRef(t, currentModule, knownModules) {
  const { name, module, parameters } = t;
  const params = parameters ?? [];

  const renderParams = () =>
    params.length > 0
      ? `<${params.map((p) => renderType(p, currentModule, knownModules)).join(", ")}>`
      : "";

  if (module === "gleam" && name === "String") return "string";
  if (module === "gleam" && name === "Int") return "number";
  if (module === "gleam" && name === "Float") return "number";
  if (module === "gleam" && name === "Bool") return "boolean";
  if (module === "gleam" && name === "Nil") return "null";
  if (module === "gleam" && name === "BitArray") return "Uint8Array";
  if (module === "gleam" && name === "List") {
    return `Array<${renderType(params[0] ?? { kind: "named", module: "gleam", name: "Nil", parameters: [] }, currentModule, knownModules)}>`;
  }
  if (module === "gleam/option" && name === "Option") {
    return `${renderType(params[0] ?? { kind: "named", module: "gleam", name: "Nil", parameters: [] }, currentModule, knownModules)} | null`;
  }
  if (module === "gleam" && name === "Result") {
    const ok = renderType(params[0] ?? { kind: "named", module: "gleam", name: "Nil", parameters: [] }, currentModule, knownModules);
    const err = renderType(params[1] ?? { kind: "named", module: "gleam", name: "Nil", parameters: [] }, currentModule, knownModules);
    return `{ tag: "Ok"; value: ${ok} } | { tag: "Error"; error: ${err} }`;
  }
  if (module === "gleam" && name === "Dict") {
    const k = renderType(params[0] ?? { kind: "named", module: "gleam", name: "String", parameters: [] }, currentModule, knownModules);
    const v = renderType(params[1] ?? { kind: "named", module: "gleam", name: "Nil", parameters: [] }, currentModule, knownModules);
    return `Array<[${k}, ${v}]>`;
  }

  if (knownModules.has(module)) {
    if (module === currentModule) {
      return `${name}${renderParams()}`;
    }
    return `${sanitizeModuleNamespace(module)}.${name}${renderParams()}`;
  }

  return "unknown";
}

function renderType(t, currentModule, knownModules) {
  if (!t || typeof t !== "object") return "unknown";

  switch (t.kind) {
    case "named":
      return namedTypeRef(t, currentModule, knownModules);
    case "tuple":
      return `[${(t.elements ?? [])
        .map((el) => renderType(el, currentModule, knownModules))
        .join(", ")}]`;
    case "fn":
      return "(...args: Array<unknown>) => unknown";
    case "variable":
      return t.name ?? "unknown";
    default:
      return "unknown";
  }
}

function renderConstructorShape(cons, currentModule, knownModules) {
  const params = cons.parameters ?? [];
  const fields = params.map((p, i) => {
    const fieldName = p.label ?? `_${i}`;
    return `${fieldName}: ${renderType(p.type, currentModule, knownModules)}`;
  });
  const fieldPart = fields.length > 0 ? `; ${fields.join("; ")}` : "";
  return `{ tag: "${cons.name}"${fieldPart} }`;
}

function renderModule(moduleName, moduleDef, knownModules) {
  const ns = sanitizeModuleNamespace(moduleName);
  const lines = [];
  lines.push(`export namespace ${ns} {`);

  const types = Object.entries(moduleDef.types ?? {}).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  for (const [typeName, typeDef] of types) {
    const constructors = typeDef.constructors ?? [];
    if (constructors.length === 0) {
      lines.push(`  export type ${typeName} = unknown;`);
      continue;
    }
    const union = constructors
      .map((c) => renderConstructorShape(c, moduleName, knownModules))
      .join(" | ");
    lines.push(`  export type ${typeName} = ${union};`);
  }

  const functions = Object.entries(moduleDef.functions ?? {}).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  for (const [fnName, fnDef] of functions) {
    const params = (fnDef.parameters ?? []).map((p, i) => {
      const name = p.label ?? `arg${i}`;
      return `${name}: ${renderType(p.type, moduleName, knownModules)}`;
    });
    const ret = renderType(fnDef.return, moduleName, knownModules);
    lines.push(`  export type Fn_${fnName} = (${params.join(", ")}) => ${ret};`);
  }

  lines.push("}");
  lines.push("");
  return lines.join("\n");
}

function writeIfChanged(file, content) {
  let current = "";
  try {
    current = readFileSync(file, "utf8");
  } catch {
    current = "";
  }
  if (current !== content) {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content, "utf8");
    return true;
  }
  return false;
}

mkdirSync(generatedDir, { recursive: true });
mkdirSync(interfaceDir, { recursive: true });

const interfaces = [];
for (const pkg of gleamSourcePackages) {
  const outPath = join(pkg.dir, "build", "interface.generated.json");
  run("gleam", ["export", "package-interface", "--out", outPath], pkg.dir);
  const raw = readFileSync(outPath, "utf8");
  const parsed = JSON.parse(raw);
  interfaces.push(parsed);
  writeIfChanged(
    join(interfaceDir, `${pkg.name}.interface.json`),
    JSON.stringify(parsed, null, 2) + "\n"
  );
}

const allModules = new Set();
for (const iface of interfaces) {
  for (const moduleName of Object.keys(iface.modules ?? {})) {
    allModules.add(moduleName);
  }
}

const lines = [];
lines.push("// AUTO-GENERATED FROM GLEAM PACKAGE INTERFACES.");
lines.push("// Source of truth: public Gleam types/functions in packages/policy + packages/interop");
lines.push("// Generator entrypoint: /scripts/generate-contracts.mjs");
lines.push("");

for (const iface of interfaces) {
  lines.push(`// package: ${iface.name}@${iface.version}`);
  const modules = Object.entries(iface.modules ?? {}).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  for (const [moduleName, moduleDef] of modules) {
    lines.push(renderModule(moduleName, moduleDef, allModules));
  }
}

lines.push("export type GeneratedContractStatus = \"gleam_source_of_truth\";");
lines.push("");

const changed = writeIfChanged(outputFile, lines.join("\n"));
if (changed) {
  console.log("Updated generated/contracts.generated.ts");
} else {
  console.log("generated/contracts.generated.ts is up to date");
}
