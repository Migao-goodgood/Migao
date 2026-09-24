import http from "node:http";
import { createHash, timingSafeEqual } from "node:crypto";
import { pathToFileURL } from "node:url";
import { AnalysisError, MAX_REQUEST_BYTES, validateRequest } from "./contract.mjs";
import { createVisionAnalyzer } from "./provider.mjs";

const hash = (value) => createHash("sha256").update(value).digest();

export function readConfig(env = process.env) {
  const apiKey = env.OPENAI_API_KEY?.trim();
  const model = env.OPENAI_VISION_MODEL?.trim();
  const clientToken = env.DIET_AI_CLIENT_TOKEN?.trim();
  if (!apiKey || !model || !clientToken || clientToken.length < 32) {
    throw new Error("Set OPENAI_API_KEY, OPENAI_VISION_MODEL, and DIET_AI_CLIENT_TOKEN (at least 32 characters)");
  }
  const port = Number(env.PORT ?? "8787");
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("PORT must be an integer between 1 and 65535");
  return { apiKey, model, clientToken, port, host: env.DIET_AI_HOST?.trim() || "127.0.0.1" };
}

function readRequestJSON(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    const cleanup = () => {
      request.off("data", onData);
      request.off("end", onEnd);
      request.off("error", onError);
      request.off("aborted", onAborted);
    };
    const fail = (error) => { cleanup(); request.pause(); reject(error); };
    const onError = () => fail(new AnalysisError("INVALID_REQUEST", 400));
    const onAborted = () => fail(new AnalysisError("INVALID_REQUEST", 400));
    const onData = (chunk) => {
      size += chunk.length;
      if (size > MAX_REQUEST_BYTES) { fail(new AnalysisError("PAYLOAD_TOO_LARGE", 413)); return; }
      chunks.push(chunk);
    };
    const onEnd = () => {
      cleanup();
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
      catch { reject(new AnalysisError("INVALID_JSON", 400)); }
    };
    request.on("data", onData);
    request.on("end", onEnd);
    request.on("error", onError);
    request.on("aborted", onAborted);
  });
}

// The shared bearer and in-memory limits are intentionally private-test-only.
// Production must replace this boundary with user/session auth and distributed
// per-user quotas before exposing the service to released clients.
export function createServer({ config = readConfig(), fetchImpl = fetch, timeoutMs = 25000, maxConcurrent = 2, maxPerMinute = 12, now = Date.now } = {}) {
  if (!config.clientToken || config.clientToken.length < 32) throw new Error("A private-test client token of at least 32 characters is required");
  const expectedAuth = hash(`Bearer ${config.clientToken}`);
  const analyze = createVisionAnalyzer({ apiKey: config.apiKey, model: config.model, fetchImpl, timeoutMs });
  let active = 0;
  let windowStart = now();
  let accepted = 0;
  const server = http.createServer(async (request, response) => {
    const send = (status, body, headers = {}) => {
      if (response.destroyed) return;
      response.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Connection": "close", ...headers });
      response.end(JSON.stringify(body));
    };
    if (request.url !== "/v1/diet/analyze" || request.method !== "POST") { send(404, { error: "NOT_FOUND" }); return; }
    if (typeof request.headers.authorization !== "string" || !timingSafeEqual(hash(request.headers.authorization), expectedAuth)) {
      send(401, { error: "UNAUTHORIZED" }); return;
    }
    if (request.headers["content-type"]?.split(";")[0].trim().toLowerCase() !== "application/json" || (request.headers["content-encoding"] && request.headers["content-encoding"] !== "identity")) {
      send(415, { error: "UNSUPPORTED_MEDIA_TYPE" }); return;
    }
    if (Number(request.headers["content-length"]) > MAX_REQUEST_BYTES) { send(413, { error: "PAYLOAD_TOO_LARGE" }); return; }
    const time = now();
    if (time - windowStart >= 60000) { windowStart = time; accepted = 0; }
    if (active >= maxConcurrent || accepted >= maxPerMinute) { send(429, { error: "RATE_LIMITED" }, { "Retry-After": "60" }); return; }
    active += 1;
    accepted += 1;
    try {
      const images = validateRequest(await readRequestJSON(request));
      if (!request.destroyed || request.complete) send(200, await analyze(images));
    } catch (error) {
      const safe = error instanceof AnalysisError ? error : new AnalysisError("INTERNAL_ERROR", 500);
      send(safe.httpStatus, { error: safe.code });
    } finally {
      active -= 1;
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.timeout = 40000;
  server.maxConnections = 16;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = readConfig();
    const server = createServer({ config });
    server.on("error", () => { console.error("diet-ai: failed to start; check bind address and port"); process.exitCode = 1; });
    server.listen(config.port, config.host, () => console.log(`diet-ai private-test service listening on ${config.host}:${config.port}`));
    for (const signal of ["SIGTERM", "SIGINT"]) process.once(signal, () => server.close());
  } catch (error) {
    // Configuration failures only, without echoing any configured value.
    console.error(`diet-ai: ${error.message}`);
    process.exitCode = 1;
  }
}
