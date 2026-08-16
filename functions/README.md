# FeedbackToMe — Cloud Functions (`aiSummary`)

Trusted **server-side OpenAI gateway**. The OpenAI key must NOT live in the
Flutter client; this 2nd-gen HTTPS callable holds `OPENAI_API_KEY` server-side,
verifies the Firebase Auth context the client already has, enforces payload +
rate limits, and calls OpenAI with a **server-chosen** model/prompt.

## What it fixes (P0)
Removes the client-side OpenAI key exposure. The old client
(`lib/services/openai_audience_client.dart`) called `api.openai.com` directly
with a compile-time-baked `OPENAI_API_KEY`. Now the client calls `aiSummary`
(Firebase callable) and never sees the key, the OpenAI Authorization header, or
raw provider responses.

## Design (not a generic proxy)
The client can submit **only** feedback-derived content. It CANNOT submit
`model`, `messages`, `systemPrompt`, `temperature`, `apiKey`, `providerUrl`, or
`response_format` — those are rejected. The server owns:

- model `gpt-4o-mini` (Chat Completions — unchanged this PR)
- endpoint, temperature (0.28), token caps, timeout, `response_format`
- the two operation prompts (`partial_digest`, `refine_report`)

The security-critical logic is in `src/ai-core.ts` and is unit-tested with **no
network and no emulator** (`test/ai-core.test.mjs`, injected `fetch`).

### Contract
Request (client → function):
```
{ operation: 'partial_digest' | 'refine_report',
  lang: 'tr' | 'en',
  // partial_digest:
  chunkIndex?, chunkTotal?, items: [{ mood:-1|0|1, relation, survey, text }],
  // refine_report:
  heuristic: <report JSON>, partialsDigest?, surveyAggregate? }
```
Response: `{ ok:true, content:"<model JSON string>", meta:{ model, clientRequestId, openaiRequestId, latencyMs, usage } }`.
Any failure throws an `HttpsError` (unauthenticated / invalid-argument /
resource-exhausted / unavailable / internal) with a stable `errorCode` — the
Flutter client catches it and falls back to the local heuristic report.

## Requirements
- **Firebase Blaze plan** (a function calling OpenAI needs egress HTTPS).
- Node 20 runtime.

## Secret (configure BEFORE deploy — do NOT commit a key)
`aiSummary` binds a single secret, `OPENAI_API_KEY`:
```bash
firebase functions:secrets:set OPENAI_API_KEY
```
⚠️ **Rotate the key first.** Any OpenAI key ever shipped in a client build must
be treated as compromised; set a freshly rotated key here, not the old one.

## Build / test
```bash
cd functions
npm install
npm run typecheck
npm test          # builds + runs node --test (network-free)
```

## Deploy (NOT done in this PR)
```bash
firebase deploy --only functions
```

## App Check activation (follow-up)
`enforceAppCheck` is **false** because the Flutter app does not send App Check
tokens today. When the client is App Check-ready (`firebase_app_check`
initialized on iOS/Android), flip `enforceAppCheck: true` in
`src/index.ts` and redeploy. Firebase Auth is required regardless.

## Rate limit / abuse control
Per-user fixed window (`aiUsage/{uid}`, default 120 calls/hour) via an atomic
Admin-SDK transaction. Admin writes bypass security rules and the collection is
default-denied to clients, so **no `firestore.rules` change is required**. There
is intentionally no per-call cooldown (a single analysis makes many chunk calls
in quick succession).

## Observability
PII-safe structured events (`openai.request.completed|failed`,
`openai.rate_limited`, `openai.timeout`) — codes/metrics only, never prompt /
feedback / completion / key / token / uid. The existing
`ops/monitor/checks/gcp-functions-logs.mjs` collector classifies these by
severity; capturing the richer OpenAI metadata (tokens, latency,
`openaiRequestId`) needs a **separate** ops-side collector update.

## Note on merging with `iapVerify`
The `feature/simple-summary-and-icon` branch adds a separate `iapVerify`
function under `functions/`. When both land, merge the two `src/index.ts`
exports and union the `dependencies` (this function needs only `firebase-admin`
+ `firebase-functions`; `iapVerify` also needs `google-auth-library`).
`initializeApp()` here is guarded with `getApps().length` so double-init is safe.
