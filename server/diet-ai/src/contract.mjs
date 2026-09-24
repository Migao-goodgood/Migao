import { createHash } from "node:crypto";

export const SCHEMA_VERSION = "diet-1";
export const MAX_IMAGES = 6;
export const MAX_DECODED_BYTES = 8_000_000;
export const MAX_REQUEST_BYTES = 12_000_000;
export const MIN_CONFIDENCE = 0.45;

export class AnalysisError extends Error {
  constructor(code, httpStatus) {
    super(code);
    this.code = code;
    this.httpStatus = httpStatus;
  }
}

function exactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function matchesSignature(bytes, mime) {
  if (mime === "image/jpeg") return bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (mime === "image/png") return bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (mime === "image/webp") return bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP";
  return false;
}

// Do not infer calories from headers or OCR. Validation only establishes the
// image transport contract; the provider must decide whether a photo is usable.
export function validateRequest(body) {
  if (!exactKeys(body, ["schema_version", "images"]) || body.schema_version !== SCHEMA_VERSION
    || !Array.isArray(body.images) || body.images.length < 1 || body.images.length > MAX_IMAGES) {
    throw new AnalysisError("INVALID_REQUEST", 400);
  }
  const unique = [];
  const seen = new Set();
  let decodedBytes = 0;
  for (const item of body.images) {
    if (typeof item?.image_base64 === "string" && item.image_base64.length > Math.ceil(MAX_DECODED_BYTES / 3) * 4) {
      throw new AnalysisError("PAYLOAD_TOO_LARGE", 413);
    }
    if (!exactKeys(item, ["image_base64", "mime_type"]) || typeof item.image_base64 !== "string"
      || item.image_base64.length === 0
      || item.image_base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(item.image_base64)
      || !["image/jpeg", "image/png", "image/webp"].includes(item.mime_type)) {
      throw new AnalysisError("INVALID_IMAGE", 422);
    }
    const bytes = Buffer.from(item.image_base64, "base64");
    if (bytes.toString("base64") !== item.image_base64 || !matchesSignature(bytes, item.mime_type)) {
      throw new AnalysisError("INVALID_IMAGE", 422);
    }
    decodedBytes += bytes.length;
    // Count bytes before deduplicating so repeating one image cannot bypass limits.
    if (decodedBytes > MAX_DECODED_BYTES) throw new AnalysisError("PAYLOAD_TOO_LARGE", 413);
    const digest = createHash("sha256").update(bytes).digest("hex");
    if (!seen.has(digest)) {
      seen.add(digest);
      unique.push(item);
    }
  }
  return unique;
}

export const RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    is_food: { type: "boolean" },
    calories_kcal: { type: ["integer", "null"] },
    confidence: { type: "number" },
    portion_description: { type: "string" },
    notes: { type: "string" }
  },
  required: ["is_food", "calories_kcal", "confidence", "portion_description", "notes"]
};

export function validateResult(value) {
  if (!exactKeys(value, RESULT_SCHEMA.required) || typeof value.is_food !== "boolean"
    || !Number.isFinite(value.confidence) || value.confidence < 0 || value.confidence > 1
    || typeof value.portion_description !== "string" || value.portion_description.length > 600
    || typeof value.notes !== "string" || value.notes.length > 1200
    || (value.calories_kcal !== null && (!Number.isInteger(value.calories_kcal) || value.calories_kcal < 0 || value.calories_kcal > 20000))) {
    throw new AnalysisError("MODEL_INVALID", 502);
  }
  // Missing/uncertain/non-food energy is null even if the model violates the
  // prompt's null rule. Genuine zero (e.g. plain water) remains distinguishable.
  return {
    schema_version: SCHEMA_VERSION,
    ...value,
    calories_kcal: value.is_food && value.confidence >= MIN_CONFIDENCE ? value.calories_kcal : null
  };
}
