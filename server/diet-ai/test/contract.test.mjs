import test from "node:test";
import assert from "node:assert/strict";
import { AnalysisError, MAX_DECODED_BYTES, validateRequest, validateResult } from "../src/contract.mjs";

const photo = (bytes = Buffer.from([255, 216, 255, 224])) => ({ image_base64: bytes.toString("base64"), mime_type: "image/jpeg" });
const meal = (images = [photo()]) => ({ schema_version: "diet-1", images });
const estimate = (overrides = {}) => ({ is_food: true, calories_kcal: 520, confidence: 0.8, portion_description: "画面中约一人份", notes: "估算，烹调用油可能导致偏差", ...overrides });
const rejectsCode = (code, status) => (error) => error instanceof AnalysisError && error.code === code && error.httpStatus === status;

test("one batch preserves distinct images and removes exact repeats", () => {
  const first = photo();
  const second = photo(Buffer.from([255, 216, 255, 225]));
  assert.deepEqual(validateRequest(meal([first, first, second])), [first, second]);
});

test("image count and schema are strict", () => {
  for (const body of [null, {}, meal([]), meal(Array(7).fill(photo())), { ...meal(), schema_version: "other" }, { ...meal(), user: "extra" }]) {
    assert.throws(() => validateRequest(body), rejectsCode("INVALID_REQUEST", 400));
  }
});

test("requires canonical base64 and matching supported image signatures", () => {
  for (const item of [
    { image_base64: "", mime_type: "image/jpeg" },
    { image_base64: "////=", mime_type: "image/jpeg" },
    { image_base64: "data:image/jpeg;base64,/9j/4A==", mime_type: "image/jpeg" },
    { image_base64: "not image".toString(), mime_type: "image/jpeg" },
    { image_base64: Buffer.from("not jpeg").toString("base64"), mime_type: "image/jpeg" },
    { ...photo(), mime_type: "image/png" },
    { ...photo(), mime_type: "text/html" },
    { ...photo(), extra: 1 }
  ]) assert.throws(() => validateRequest(meal([item])), rejectsCode("INVALID_IMAGE", 422));
  assert.equal(validateRequest(meal([{ mime_type: "image/png", image_base64: Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).toString("base64") }])).length, 1);
  assert.equal(validateRequest(meal([{ mime_type: "image/webp", image_base64: Buffer.from("RIFF0000WEBP").toString("base64") }])).length, 1);
});

test("8,000,000 byte budget counts duplicates before deduplication", () => {
  const bytes = Buffer.alloc(MAX_DECODED_BYTES / 2);
  bytes.set([255, 216, 255, 224]);
  const large = photo(bytes);
  assert.equal(validateRequest(meal([large, large])).length, 1);
  assert.throws(() => validateRequest(meal([large, large, photo()])), rejectsCode("PAYLOAD_TOO_LARGE", 413));
  const singleTooBig = Buffer.alloc(MAX_DECODED_BYTES + 1);
  singleTooBig.set([255, 216, 255, 224]);
  assert.throws(() => validateRequest(meal([photo(singleTooBig)])), rejectsCode("PAYLOAD_TOO_LARGE", 413));
});

test("unknown and non-food never become zero, but true zero is retained", () => {
  assert.equal(validateResult(estimate({ calories_kcal: null })).calories_kcal, null);
  assert.equal(validateResult(estimate({ is_food: false, calories_kcal: 0 })).calories_kcal, null);
  assert.equal(validateResult(estimate({ confidence: 0.449 })).calories_kcal, null);
  assert.equal(validateResult(estimate({ confidence: 0.45 })).calories_kcal, 520);
  assert.equal(validateResult(estimate({ calories_kcal: 0 })).calories_kcal, 0);
});

test("rejects missing, extra, invalid-range, and oversized model fields", () => {
  for (const invalid of [
    {}, [], { ...estimate(), extra: true }, estimate({ is_food: "true" }),
    estimate({ calories_kcal: -1 }), estimate({ calories_kcal: 20001 }), estimate({ calories_kcal: 1.2 }), estimate({ calories_kcal: "520" }),
    estimate({ confidence: NaN }), estimate({ confidence: 1.01 }), estimate({ confidence: -0.1 }), estimate({ confidence: "0.8" }),
    estimate({ portion_description: "x".repeat(601) }), estimate({ notes: "x".repeat(1201) })
  ]) assert.throws(() => validateResult(invalid), rejectsCode("MODEL_INVALID", 502));
});
