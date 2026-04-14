import { spawnSync } from "node:child_process";

const mode = process.argv[2];

const packageDirs = [
  "packages/policy",
  "packages/interop",
  "apps/oxcore",
  "apps/oxradius",
  "apps/oxnoc",
  "apps/oxolt",
  "apps/oxbill"
];

const commandByMode = {
  build: ["gleam", ["build"]],
  test: ["gleam", ["test"]],
  check: ["gleam", ["check"]],
  "format-check": ["gleam", ["format", "--check", "src", "test"]]
};

if (!mode || !commandByMode[mode]) {
  console.error(
    `Unknown mode '${mode}'. Expected one of: ${Object.keys(commandByMode).join(", ")}`
  );
  process.exit(1);
}

const [cmd, args] = commandByMode[mode];

for (const cwd of packageDirs) {
  console.log(`\n==> ${cwd}: ${cmd} ${args.join(" ")}`);
  const result = spawnSync(cmd, args, { cwd, stdio: "inherit" });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
