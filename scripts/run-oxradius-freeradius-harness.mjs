import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const execute = args.includes("--execute");

const host = readFlag("--host", "127.0.0.1");
const secret = readFlag("--secret", "sharedsecret");
const user = readFlag("--user", "sub_1");
const password = readFlag("--password", "test123");
const authPort = readFlag("--auth-port", "1812");
const coaPort = readFlag("--coa-port", "3799");

const requestRoot = path.join(
  process.cwd(),
  "apps",
  "oxradius",
  "test",
  "harness",
  "freeradius",
  "requests"
);

const statusRequest = path.join(requestRoot, "status-request.txt");
const coaRequest = path.join(requestRoot, "coa-request.txt");
const disconnectRequest = path.join(requestRoot, "disconnect-request.txt");

const commands = [
  {
    name: "radtest-access-request",
    cmd: "radtest",
    args: [user, password, host, "0", secret],
    optional: true
  },
  {
    name: "radclient-status-server",
    cmd: "radclient",
    args: [`${host}:${authPort}`, "status", secret, "<", statusRequest],
    optional: false
  },
  {
    name: "radclient-coa",
    cmd: "radclient",
    args: [`${host}:${coaPort}`, "coa", secret, "<", coaRequest],
    optional: false
  },
  {
    name: "radclient-disconnect",
    cmd: "radclient",
    args: [`${host}:${coaPort}`, "disconnect", secret, "<", disconnectRequest],
    optional: false
  }
];

for (const requestPath of [statusRequest, coaRequest, disconnectRequest]) {
  if (!existsSync(requestPath)) {
    console.error(`Missing request fixture: ${requestPath}`);
    process.exit(1);
  }
}

console.log("oxRADIUS FreeRADIUS harness");
console.log(`mode: ${execute ? "execute" : "dry-run"}`);
console.log(`target: ${host}, auth-port=${authPort}, coa-port=${coaPort}`);
console.log("");

for (const command of commands) {
  const rendered = `${command.cmd} ${command.args.join(" ")}`;
  console.log(`[${command.name}] ${rendered}`);

  if (!execute) {
    continue;
  }

  const runner = spawnSync(
    process.platform === "win32" ? "cmd.exe" : "sh",
    process.platform === "win32"
      ? ["/d", "/s", "/c", rendered]
      : ["-lc", rendered],
    { stdio: "inherit" }
  );

  if (runner.status !== 0) {
    if (command.optional) {
      console.warn(
        `[${command.name}] skipped/failed (optional), continuing with remaining commands`
      );
      continue;
    }

    console.error(`[${command.name}] failed with exit code ${runner.status}`);
    process.exit(runner.status ?? 1);
  }
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
