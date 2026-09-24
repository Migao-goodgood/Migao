import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { once } from "node:events";
import { createServer, readConfig } from "../src/server.mjs";
import { MAX_REQUEST_BYTES } from "../src/contract.mjs";

const token = "private-local-test-token-000000000000";
const config = { apiKey: "mock-key", model: "mock-model", clientToken: token };
const meal = { schema_version: "diet-1", images: [{ image_base64: "/9j/4A==", mime_type: "image/jpeg" }] };
const upstream = () => new Response(JSON.stringify({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify({ is_food: true, calories_kcal: 500, confidence: 0.8, portion_description: "一人份", notes: "估算，份量可能有误差" }) }] }] }));

async function start(t, options = {}) {
  // All provider traffic is replaced; the only listener is an ephemeral local
  // HTTP test server, never a deployed or real-provider service.
  const server = createServer({ config, fetchImpl: async () => upstream(), ...options });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(async () => { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); });
  return server.address().port;
}

function request(port, body = meal, headers = {}, path = "/v1/diet/analyze") {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: "127.0.0.1", port, path, method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, ...headers } }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("error", reject);
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: JSON.parse(Buffer.concat(chunks).toString()) }));
    });
    req.on("error", reject);
    req.end(typeof body === "string" ? body : JSON.stringify(body));
  });
}

test("configuration rejects missing keys/model/auth and has no model default", () => {
  assert.throws(() => readConfig({}));
  assert.throws(() => readConfig({ OPENAI_API_KEY: "mock", DIET_AI_CLIENT_TOKEN: token }));
  assert.throws(() => readConfig({ OPENAI_API_KEY: "mock", OPENAI_VISION_MODEL: "mock", DIET_AI_CLIENT_TOKEN: "weak" }));
  const valid = readConfig({ OPENAI_API_KEY: "mock", OPENAI_VISION_MODEL: "chosen-model", DIET_AI_CLIENT_TOKEN: token });
  assert.equal(valid.host, "127.0.0.1");
  assert.equal(valid.model, "chosen-model");
});

test("unauthorized requests never consume a provider call", async (t) => {
  let calls = 0;
  const port = await start(t, { fetchImpl: async () => { calls += 1; return upstream(); } });
  const rejected = await request(port, meal, { Authorization: "Bearer invalid" });
  assert.equal(rejected.status, 401);
  assert.deepEqual(rejected.body, { error: "UNAUTHORIZED" });
  assert.equal(calls, 0);
  const accepted = await request(port);
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.calories_kcal, 500);
  assert.equal(accepted.headers["cache-control"], "no-store");
  assert.equal(calls, 1);
});

test("validates transport, JSON and image content before provider calls", async (t) => {
  let calls = 0;
  const port = await start(t, { fetchImpl: async () => { calls += 1; return upstream(); } });
  assert.equal((await request(port, meal, {}, "/wrong")).status, 404);
  assert.equal((await request(port, meal, { "Content-Type": "text/plain" })).status, 415);
  assert.equal((await request(port, meal, { "Content-Encoding": "gzip" })).status, 415);
  assert.equal((await request(port, "{")).status, 400);
  assert.equal((await request(port, { ...meal, images: [] })).status, 400);
  assert.equal((await request(port, { ...meal, images: [{ image_base64: "AAAA", mime_type: "image/jpeg" }] })).status, 422);
  assert.equal(calls, 0);
});

test("rejects declared and streamed bodies over 12,000,000 bytes", async (t) => {
  const port = await start(t);
  assert.equal((await request(port, "", { "Content-Length": String(MAX_REQUEST_BYTES + 1) })).status, 413);
  const result = await request(port, " ".repeat(MAX_REQUEST_BYTES + 1));
  assert.equal(result.status, 413);
  assert.deepEqual(result.body, { error: "PAYLOAD_TOO_LARGE" });
});

test("bounded request rate resets after a minute", async (t) => {
  let time = 100;
  const port = await start(t, { maxPerMinute: 1, now: () => time });
  assert.equal((await request(port)).status, 200);
  const blocked = await request(port);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.headers["retry-after"], "60");
  time += 60000;
  assert.equal((await request(port)).status, 200);
});

test("concurrency limit is released after completion", async (t) => {
  let notifyStarted;
  let release;
  const started = new Promise((resolve) => { notifyStarted = resolve; });
  const gate = new Promise((resolve) => { release = resolve; });
  const port = await start(t, { maxConcurrent: 1, fetchImpl: async () => { notifyStarted(); await gate; return upstream(); } });
  const first = request(port);
  await started;
  assert.equal((await request(port)).status, 429);
  release();
  assert.equal((await first).status, 200);
  assert.equal((await request(port)).status, 200);
});

test("returns explicit safe API refusal codes", async (t) => {
  const port = await start(t, { fetchImpl: async () => new Response(JSON.stringify({ status: "completed", output: [{ type: "message", content: [{ type: "refusal", refusal: "provider private details" }] }] })) });
  const result = await request(port);
  assert.equal(result.status, 422);
  assert.deepEqual(result.body, { error: "MODEL_REFUSED" });
});
