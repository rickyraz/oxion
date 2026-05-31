import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const execute = args.includes("--execute");
const strictStatus = args.includes("--strict-status");

const host = readFlag("--host", process.env.OXRADIUS_REMOTE_HOST ?? "101.255.3.165");
const authPort = readFlag(
  "--auth-port",
  process.env.OXRADIUS_REMOTE_AUTH_PORT ?? "1812"
);
const acctPort = readFlag(
  "--acct-port",
  process.env.OXRADIUS_REMOTE_ACCT_PORT ?? "1813"
);
const secret = readFlag(
  "--secret",
  process.env.OXRADIUS_REMOTE_SECRET ?? "SecretRADIUS2024!"
);
const user = readFlag("--user", process.env.OXRADIUS_REMOTE_USER ?? "testing");
const password = readFlag(
  "--password",
  process.env.OXRADIUS_REMOTE_PASSWORD ?? "testing123"
);
const sessionId = readFlag(
  "--session-id",
  process.env.OXRADIUS_REMOTE_SESSION_ID ?? "oxradius-remote-test-001"
);

const authRequest = [
  `User-Name = ${quoteRadius(user)}`,
  `User-Password = ${quoteRadius(password)}`
].join(", ");

const accountingRequest = [
  `User-Name = ${quoteRadius(user)}`,
  "Acct-Status-Type = Start",
  `Acct-Session-Id = ${quoteRadius(sessionId)}`
].join(", ");

const statusRequest = [
  "Packet-Type := Status-Server",
  "Message-Authenticator := 0x00"
].join(", ");

const commands = [
  {
    name: "radtest-access-request",
    rendered: `radtest ${shellQuote(user)} ${shellQuote(password)} ${shellQuote(
      host
    )} 0 ${shellQuote(secret)}`,
    required: true,
    expect: ["Access-Accept"]
  },
  {
    name: "radclient-auth-request",
    rendered: `printf '%s\\n' ${shellQuote(authRequest)} | radclient ${shellQuote(
      `${host}:${authPort}`
    )} auth ${shellQuote(secret)}`,
    required: true,
    expect: ["Access-Accept"]
  },
  {
    name: "radclient-status-server",
    rendered: `printf '%s\\n' ${shellQuote(
      statusRequest
    )} | radclient ${shellQuote(`${host}:${authPort}`)} status ${shellQuote(
      secret
    )}`,
    required: strictStatus,
    expect: []
  },
  {
    name: "radclient-accounting-start",
    rendered: `printf '%s\\n' ${shellQuote(
      accountingRequest
    )} | radclient ${shellQuote(`${host}:${acctPort}`)} acct ${shellQuote(
      secret
    )}`,
    required: true,
    expect: ["Accounting-Response"]
  }
];

console.log("oxRADIUS remote FreeRADIUS test");
console.log(`mode: ${execute ? "execute" : "dry-run"}`);
console.log(`target: ${host}, auth-port=${authPort}, acct-port=${acctPort}`);
console.log(`user: ${user}`);
console.log(`strict-status: ${strictStatus ? "yes" : "no"}`);
console.log("");

for (const command of commands) {
  console.log(`[${command.name}] ${command.rendered}`);

  if (!execute) {
    continue;
  }

  const runner = spawnSync("sh", ["-lc", command.rendered], {
    encoding: "utf8"
  });

  const output = `${runner.stdout ?? ""}${runner.stderr ?? ""}`;
  if (output.trim() !== "") {
    console.log(output.trimEnd());
  }

  if (runner.status !== 0) {
    if (!command.required) {
      console.warn(
        `[${command.name}] failed/skipped (optional), continuing with remaining commands`
      );
      continue;
    }

    console.error(`[${command.name}] failed with exit code ${runner.status}`);
    process.exit(runner.status ?? 1);
  }

  for (const expected of command.expect) {
    if (!output.includes(expected)) {
      console.error(
        `[${command.name}] missing expected output fragment: ${expected}`
      );
      process.exit(1);
    }
  }

  console.log(`[${command.name}] passed`);
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

function quoteRadius(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}
