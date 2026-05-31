import { createServer } from "node:http";
import { mkdirSync, appendFileSync } from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const port = Number.parseInt(
  readFlag("--port", process.env.OXRADIUS_RLM_REST_PORT ?? "8088"),
  10
);
const host = readFlag("--host", process.env.OXRADIUS_RLM_REST_HOST ?? "127.0.0.1");
const token = readFlag("--token", process.env.OXRADIUS_RLM_REST_TOKEN ?? "");
const evidenceDir = readFlag(
  "--evidence-dir",
  process.env.OXRADIUS_RLM_REST_EVIDENCE_DIR ??
    "evidence/oxradius-rlm-rest-callback"
);
const evidencePath = path.join(process.cwd(), evidenceDir, "callbacks.jsonl");

if (!Number.isInteger(port) || port <= 0 || port > 65_535) {
  console.error("Invalid --port value");
  process.exit(1);
}

if (token.trim() === "") {
  console.error(
    "Missing token. Set OXRADIUS_RLM_REST_TOKEN or pass --token <value>."
  );
  process.exit(1);
}

mkdirSync(path.dirname(evidencePath), { recursive: true });

const server = createServer(async (req, res) => {
  const startedAt = new Date();
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  const body = await readBody(req);
  const authorized = req.headers.authorization === `Bearer ${token}`;

  if (req.method === "GET" && url.pathname === "/health") {
    writeJson(res, 200, { status: "ok" });
    writeEvidence({
      timestamp: startedAt.toISOString(),
      method: req.method,
      path: url.pathname,
      authorized,
      status: 200,
      body: parseJsonOrText(body),
      response: { status: "ok" }
    });
    return;
  }

  if (!authorized) {
    const response = { error: "unauthorized" };
    writeJson(res, 401, response);
    writeEvidence({
      timestamp: startedAt.toISOString(),
      method: req.method,
      path: url.pathname,
      authorized,
      status: 401,
      body: parseJsonOrText(body),
      response
    });
    console.log(`[401] ${req.method} ${url.pathname}`);
    return;
  }

  if (req.method !== "POST") {
    const response = { error: "method_not_allowed" };
    writeJson(res, 405, response);
    writeEvidence({
      timestamp: startedAt.toISOString(),
      method: req.method,
      path: url.pathname,
      authorized,
      status: 405,
      body: parseJsonOrText(body),
      response
    });
    console.log(`[405] ${req.method} ${url.pathname}`);
    return;
  }

  const parsedBody = parseJsonOrText(body);
  const response = responseForPath(url.pathname);

  if (!response) {
    const notFound = { error: "not_found" };
    writeJson(res, 404, notFound);
    writeEvidence({
      timestamp: startedAt.toISOString(),
      method: req.method,
      path: url.pathname,
      authorized,
      status: 404,
      body: parsedBody,
      response: notFound
    });
    console.log(`[404] ${req.method} ${url.pathname}`);
    return;
  }

  writeJson(res, 200, response);
  writeEvidence({
    timestamp: startedAt.toISOString(),
    method: req.method,
    path: url.pathname,
    authorized,
    status: 200,
    headers: selectedHeaders(req.headers),
    body: parsedBody,
    response
  });
  console.log(`[200] ${req.method} ${url.pathname}`);
  console.log(JSON.stringify({ body: parsedBody, response }, null, 2));
});

server.listen(port, host, () => {
  console.log("oxRADIUS rlm_rest callback server");
  console.log(`listen: http://${host}:${port}`);
  console.log(`evidence: ${evidencePath}`);
  console.log("endpoints:");
  console.log("  GET  /health");
  console.log("  POST /v1/policy/authorize");
  console.log("  POST /v1/policy/accounting");
  console.log("  POST /v1/policy/post-auth");
});

function responseForPath(pathname) {
  switch (pathname) {
    case "/v1/policy/authorize":
      return {
        "Reply-Message": {
          op: ":=",
          value: ["oxRADIUS callback accepted"]
        }
      };
    case "/v1/policy/accounting":
      return {
        result: "ok",
        action: "accounting_ack"
      };
    case "/v1/policy/post-auth":
      return {
        result: "ok",
        action: "post_auth_ack"
      };
    default:
      return null;
  }
}

function writeJson(res, status, payload) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(`${JSON.stringify(payload)}\n`);
}

function writeEvidence(entry) {
  appendFileSync(evidencePath, `${JSON.stringify(entry)}\n`);
}

function selectedHeaders(headers) {
  return {
    "content-type": headers["content-type"],
    "user-agent": headers["user-agent"],
    "x-forwarded-for": headers["x-forwarded-for"],
    "cf-connecting-ip": headers["cf-connecting-ip"]
  };
}

function parseJsonOrText(body) {
  if (body.trim() === "") {
    return null;
  }

  try {
    return JSON.parse(body);
  } catch {
    return body;
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        req.destroy(new Error("request_body_too_large"));
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
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
