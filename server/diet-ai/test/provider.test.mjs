import test from "node:test";
import assert from "node:assert/strict";
import { createVisionAnalyzer } from "../src/provider.mjs";

const images = [{ image_base64: "/9j/4A==", mime_type: "image/jpeg" }];
const estimate = { is_food: true, calories_kcal: 520, confidence: 0.8, portion_description: "一人份可见餐食", notes: "估算，油和酱汁用量不确定" };
const complete = (value = estimate) => ({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify(value) }] }] });
const response = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const analyzer = (fetchImpl, extra = {}) => createVisionAnalyzer({ apiKey: "mock-provider-secret", model: "mock-vision-model", fetchImpl, ...extra });

test("calls only Responses endpoint with image input, strict schema and store false", async () => {
  let sent;
  let count = 0;
  const analyze = analyzer(async (url, options) => {
    count += 1;
    assert.equal(url, "https://api.openai.com/v1/responses");
    assert.equal(options.redirect, "error");
    assert.equal(options.headers.Authorization, "Bearer mock-provider-secret");
    sent = JSON.parse(options.body);
    return response(complete());
  });
  const result = await analyze(images);
  assert.equal(count, 1);
  assert.deepEqual(result, { schema_version: "diet-1", ...estimate });
  assert.equal(sent.store, false);
  assert.equal(sent.model, "mock-vision-model");
  assert.equal(sent.text.format.type, "json_schema");
  assert.equal(sent.text.format.strict, true);
  assert.equal(sent.input[0].content[0].image_url, "data:image/jpeg;base64,/9j/4A==");
  assert.match(sent.instructions, /Count the same food once/);
  assert.match(sent.instructions, /Do not return food names/);
});

test("refusals and incomplete output have explicit safe errors", async () => {
  for (const [payload, code] of [
    [{ status: "completed", output: [{ type: "message", content: [{ type: "refusal", refusal: "raw-provider-refusal-must-not-escape" }] }] }, "MODEL_REFUSED"],
    [{ status: "incomplete", output: [] }, "MODEL_INCOMPLETE"],
    [{ status: "failed", output: [] }, "UPSTREAM_INVALID"]
  ]) {
    await assert.rejects(analyzer(async () => response(payload))(images), (error) => error.code === code && !error.message.includes("raw-provider"));
  }
});

test("rejects malformed provider JSON, malformed model JSON and invalid shape", async () => {
  const cases = [
    [() => new Response("not json"), "UPSTREAM_INVALID"],
    [() => response({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: "```json\n{}\n```" }] }] }), "MODEL_INVALID"],
    [() => response(complete({ ...estimate, calories_kcal: 20001 })), "MODEL_INVALID"],
    [() => response(complete({})), "MODEL_INVALID"],
    [() => response({ status: "completed", output: [] }), "MODEL_INVALID"]
  ];
  for (const [makeResponse, code] of cases) await assert.rejects(analyzer(async () => makeResponse())(images), { code });
});

test("provider failures are sanitized, never retried, and never echo credentials", async () => {
  let calls = 0;
  const analyze = analyzer(async () => { calls += 1; return response({ error: "provider key mock-provider-secret request data" }, 429); });
  await assert.rejects(analyze(images), { code: "UPSTREAM_BUSY", message: "UPSTREAM_BUSY" });
  assert.equal(calls, 1);
  await assert.rejects(analyzer(async () => { throw new Error("secret details"); })(images), { code: "UPSTREAM_UNAVAILABLE", message: "UPSTREAM_UNAVAILABLE" });
});

test("abort timeout returns explicit timeout and releases timer", async () => {
  const hold = setTimeout(() => {}, 1000);
  try {
    await assert.rejects(analyzer(async (_url, options) => await new Promise((_resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")), { once: true });
    }), { timeoutMs: 5 })(images), { code: "UPSTREAM_TIMEOUT", httpStatus: 504 });
  } finally { clearTimeout(hold); }
});

test("caps upstream bytes instead of retaining unbounded responses", async () => {
  await assert.rejects(analyzer(async () => new Response(" ".repeat(128 * 1024 + 1)))(images), { code: "UPSTREAM_INVALID" });
});
