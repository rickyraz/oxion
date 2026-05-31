import { spawn, spawnSync } from "node:child_process";
import { existsSync, rmSync } from "node:fs";

const args = process.argv.slice(2);
const execute = args.includes("--execute");
const keepRunning = args.includes("--keep-running");

const backend = readFlag("--backend", "oxradius");
const token = readFlag("--token", process.env.OXRADIUS_RLM_REST_TOKEN ?? "test-token");
const callbackPort = readFlag("--callback-port", "18088");
const authPort = readFlag("--auth-port", "18120");
const acctPort = readFlag("--acct-port", "18130");
const secret = readFlag("--secret", "sharedsecret");
const user = readFlag("--user", "testing");
const password = readFlag("--password", "testing123");
const evidenceDir = readFlag(
  "--evidence-dir",
  "evidence/oxradius-rlm-rest-callback"
);

const composeFile =
  "apps/oxradius/test/harness/freeradius-rlm-rest/docker-compose.yml";

const commands = [
  {
    name: "policy-api",
    command: policyApiCommand()
  },
  {
    name: "freeradius-container",
    command: `docker compose -f ${shellQuote(composeFile)} up -d --force-recreate`
  },
  {
    name: "auth-test",
    command: `radtest ${shellQuote(user)} ${shellQuote(password)} 127.0.0.1:${shellQuote(
      authPort
    )} 0 ${shellQuote(secret)}`,
    expect: ["Access-Accept", "oxRADIUS callback accepted"]
  },
  {
    name: "accounting-test",
    command:
      `printf '%s\\n' ${shellQuote(
        'User-Name = "testing", Acct-Status-Type = Start, Acct-Session-Id = "rlm-rest-harness-001"'
      )} | radclient 127.0.0.1:${shellQuote(acctPort)} acct ${shellQuote(secret)}`,
    expect: ["Accounting-Response"]
  }
];

console.log("oxRADIUS local rlm_rest harness");
console.log(`mode: ${execute ? "execute" : "dry-run"}`);
console.log(`callback-port: ${callbackPort}`);
console.log(`auth-port: ${authPort}, acct-port: ${acctPort}`);
console.log(`evidence-dir: ${evidenceDir}`);
console.log(`backend: ${backend}`);
console.log("");

for (const command of commands) {
  console.log(`[${command.name}] ${command.command}`);
}

if (!execute) {
  process.exit(0);
}

if (!existsSync(composeFile)) {
  console.error(`Missing compose file: ${composeFile}`);
  process.exit(1);
}

rmSync(evidenceDir, { force: true, recursive: true });

let callbackProcess;
let exitCode = 0;
try {
  callbackProcess = spawn(
    "sh",
    ["-lc", commands[0].command],
    { stdio: ["ignore", "pipe", "pipe"] }
  );
  callbackProcess.stdout.on("data", (chunk) => process.stdout.write(chunk));
  callbackProcess.stderr.on("data", (chunk) => process.stderr.write(chunk));

  waitForPolicyApi(`http://127.0.0.1:${callbackPort}/health`, 60_000);

  run(commands[1]);
  sleep(2000);
  run(commands[2]);
  run(commands[3]);

  console.log("[rlm-rest-harness] passed");

  if (keepRunning) {
    console.log("[rlm-rest-harness] keeping callback server and container running");
    process.stdin.resume();
  }
} finally {
  if (!keepRunning) {
    spawnSync("docker", ["compose", "-f", composeFile, "down"], {
      stdio: "inherit"
    });
    if (callbackProcess && !callbackProcess.killed) {
      callbackProcess.kill("SIGKILL");
    }
    process.exit(exitCode);
  }
}

function policyApiCommand() {
  switch (backend) {
    case "callback":
      return (
        `OXRADIUS_RLM_REST_TOKEN=${shellQuote(token)} ` +
        `OXRADIUS_RLM_REST_EVIDENCE_DIR=${shellQuote(evidenceDir)} ` +
        `node scripts/run-oxradius-rlm-rest-callback-server.mjs ` +
        `--host 0.0.0.0 --port ${shellQuote(callbackPort)}`
      );
    case "oxradius":
      return (
        `OXRADIUS_RLM_REST_TOKEN=${shellQuote(token)} ` +
        `OXRADIUS_HTTP_BIND=0.0.0.0 ` +
        `OXRADIUS_HTTP_PORT=${shellQuote(callbackPort)} ` +
        `nix develop -c sh -lc 'cd apps/oxradius && gleam run'`
      );
    default:
      console.error(`Unsupported --backend value: ${backend}`);
      process.exit(1);
  }
}

function run(command) {
  const runner = spawnSync("sh", ["-lc", command.command], {
    encoding: "utf8"
  });
  const output = `${runner.stdout ?? ""}${runner.stderr ?? ""}`;
  if (output.trim() !== "") {
    console.log(output.trimEnd());
  }
  if (runner.status !== 0) {
    console.error(`[${command.name}] failed with exit code ${runner.status}`);
    exitCode = runner.status ?? 1;
    process.exit(runner.status ?? 1);
  }
  for (const expected of command.expect ?? []) {
    if (!output.includes(expected)) {
      console.error(`[${command.name}] missing expected output: ${expected}`);
      exitCode = 1;
      process.exit(1);
    }
  }
  console.log(`[${command.name}] passed`);
}

function waitForPolicyApi(url, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (callbackProcess.exitCode !== null) {
      console.error(`[policy-api] exited early with code ${callbackProcess.exitCode}`);
      exitCode = callbackProcess.exitCode ?? 1;
      process.exit(exitCode);
    }

    const runner = spawnSync("curl", ["-fsS", url], {
      encoding: "utf8"
    });
    if (runner.status === 0) {
      console.log("[policy-api] ready");
      return;
    }
    sleep(500);
  }

  console.error(`[policy-api] did not become ready within ${timeoutMs}ms: ${url}`);
  exitCode = 1;
  process.exit(1);
}

function readFlag(name, defaultValue) {
  const index = args.indexOf(name);
  if (index === -1) {
    return defaultValue;
  }

  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    console.error(`Flag ${name} requires a value`);
    process.exit(1);
  }

  return value;
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}
