# Diet AI: private-test service

Meal-photo calorie estimation for Migao. This service sends actual images to a configured OpenAI vision model through the Responses API; it does not mistake OCR text extraction for meal recognition. One batch represents one meal record, and the model estimates visible portions across all distinct dishes. Exact duplicate bytes are removed; the prompt tells the model not to count repeated angles of a dish twice.

**Status: source and offline mock tests only. Not deployed; no real-provider test has been performed.** A source-code implementation does not make the feature available on phones until its backend, credentials, client authentication, endpoint and user consent are configured.

## Files and boundaries

| File | Responsibility |
| --- | --- |
| `src/contract.mjs` | Versioned request/result validation, image bounds, exact-image deduplication and unknown-calorie rules |
| `src/provider.mjs` | Responses API adapter, bounded timeout/result size, structured output and safe provider errors |
| `src/server.mjs` | HTTP input, private-test bearer authentication and in-memory request/concurrency bounds |
| `test/*.test.mjs` | Offline contract/provider and loopback-only HTTP tests using injected fake fetch |

Requires Node.js 22+; no third-party packages are required. Run offline tests from this directory:

```sh
npm test
```

Tests use dummy strings, synthetic image-signature bytes and fake provider responses. They neither read a real API key nor send requests to OpenAI. Synthetic image bytes exercise transport validation, not image decoding or calorie accuracy.

## Local private testing (operator setup; not performed here)

Supply these environment variables through an untracked environment file or your secret manager:

```dotenv
OPENAI_API_KEY=<server-only-provider-key>
OPENAI_VISION_MODEL=<account-enabled-vision-model-with-structured-output-support>
DIET_AI_CLIENT_TOKEN=<random-private-test-token-of-at-least-32-characters>
# Optional: PORT=8787
# Optional: DIET_AI_HOST=127.0.0.1
```

Then start with Node's environment-file support, using a local untracked `.env`:

```sh
node --env-file=.env src/server.mjs
```

There is deliberately no assumed model default. The operator must choose an account-enabled vision model supporting Responses image inputs and strict JSON schema output. The service refuses to start when key, model or the private-test token is missing. Use a securely generated token, not the illustrative placeholders above. Keep `.env` out of git and never place the OpenAI key in the app, Info.plist, build settings, client bundle or URLs.

Default binding is `127.0.0.1:8787`. No service has been launched by this change. This HTTP listener is not a public production endpoint. An iPhone does not reach a Mac's loopback address; use a deliberately configured HTTPS development deployment/tunnel with authorization to test from a physical device. Do not weaken App Transport Security or embed a shared token to bypass that requirement.

## Client contract

`POST /v1/diet/analyze`, `Content-Type: application/json`, `Authorization: Bearer <client token>`:

```json
{
  "schema_version": "diet-1",
  "images": [{ "image_base64": "...", "mime_type": "image/jpeg" }]
}
```

At most **6 images**, **8,000,000 total decoded bytes** (counted before deduplication), and **12,000,000 request bytes**. The app prepares JPEGs; the server also recognizes PNG/WebP signatures. Base64 must be canonical, with no data-URL prefix. Signature validation is not a complete image decoder: a corrupt/unreadable image can still be rejected by the provider. Compressed HTTP bodies are not accepted.

Successful response:

```json
{
  "schema_version": "diet-1",
  "is_food": true,
  "calories_kcal": 620,
  "confidence": 0.78,
  "portion_description": "照片中约一人份可见餐食",
  "notes": "热量为估算，烹调用油和份量可能导致偏差。"
}
```

No food-name field is returned. `calories_kcal` is an integer from 0 to 20,000, or `null`. Unknown, unreadable, non-food and low-confidence (< 0.45) results remain `null`, not 0. Real zero (e.g. clearly identifiable zero-energy drink) is distinct. Model confidence is a model self-report, not a calibrated accuracy guarantee. Photos cannot reveal actual grams or all ingredients; calories remain estimates that the user can correct before confirming a record.

Error response: `{ "error": "CODE" }`. Stable codes:

| HTTP | Codes |
| --- | --- |
| 400 | `INVALID_REQUEST`, `INVALID_JSON` |
| 401 | `UNAUTHORIZED` |
| 413 | `PAYLOAD_TOO_LARGE` |
| 415 | `UNSUPPORTED_MEDIA_TYPE` |
| 422 | `INVALID_IMAGE`, `MODEL_REFUSED` |
| 429 | `RATE_LIMITED` (Retry-After header) |
| 502 | `UPSTREAM_BUSY`, `UPSTREAM_UNAVAILABLE`, `UPSTREAM_INVALID`, `MODEL_INCOMPLETE`, `MODEL_INVALID` |
| 504 | `UPSTREAM_TIMEOUT` |

There are no automatic retries: another attempt must be deliberate so model cost is not silently multiplied. Default provider timeout is 25 seconds. The private test instance accepts at most 2 concurrent requests and 12 authenticated requests per minute. These memory-only limits reset when the process restarts and are not sufficient production abuse controls.

## Privacy and production prerequisites

The app must preserve a local draft first and obtain explicit consent before transmitting photos. The backend forwards submitted image bytes to **OpenAI** at `https://api.openai.com/v1/responses`; this crosses the phone's local storage boundary. It uses `store: false`, which is **not** a promise that OpenAI has no provider-side abuse-monitoring retention. Configure and disclose the provider's applicable retention policy before deployment.

This service does not persist photos, log photo/request bodies, forward raw provider errors, or follow upstream redirects. Do not add body/Authorization logging in reverse proxies or hosting platforms. The model is instructed to ignore commands written in photos, avoid food names and medical advice, and return only a constrained estimate.

Before public use:

1. Deploy an HTTPS product-owned endpoint and server-side secret storage; select and live-validate a supported vision model on representative meal images with separate operator approval.
2. Replace the shared `DIET_AI_CLIENT_TOKEN` boundary with verified, expiring real user/session authentication. The private shared token is only for limited internal testing, injected through the client's token provider; it must **not** be compiled into a released app. Existing WeChat app launch alone is not a valid backend session.
3. Add per-user quotas, cost budgets, distributed rate limiting, monitoring without health/photo content, credential rotation, and appropriate image-upload/privacy consent and data-retention terms.
4. Configure the client endpoint and its authenticated token provider. Test refusal, timeout, non-food, small/large portions, repeated angles, editable estimates and photo-only saving on a real device. Do not label the feature connected or accurate until that validation is complete.
