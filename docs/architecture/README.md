# Feedback2Me — System Architecture

> Source of truth = the repository (code, config, deploy files). Every claim below cites `file:line`.
> This document is **discovery + model + visuals only** — no code, no deploy, no production changes.
> Generated from a 4-way read-only discovery sweep; the machine-readable model lives in
> [`component-inventory.json`](./component-inventory.json), [`dependency-graph.json`](./dependency-graph.json),
> [`user-journeys.json`](./user-journeys.json).

## Visuals

| File | What |
|---|---|
| [`system-master.html`](./system-master.html) | **Interactive** (open in a browser): 6-layer runtime + release plane, hover-highlight, click node/edge → detail panel, flow filters. Self-contained, no dependencies. |
| [`system-master.svg`](./system-master.svg) | Static at-a-glance overview. |
| [`system-master.mmd`](./system-master.mmd) | Mermaid source (renders to SVG: `mmdc -i system-master.mmd -o system-master.svg`). |
| [`diagrams/01..06-*.mmd`](./diagrams) | Focused sub-flows (owner, public feedback, premium/IAP, AI report, backend data, release pipeline). |

Node IDs are **stable** (`node-*`, `e-*`) so a future health dashboard can attach `healthy/degraded/down/unknown` state. Current status of every node = **UNKNOWN / NOT MONITORED**.

---

## System overview

Feedback2Me is a single-link anonymous feedback platform (Scenario A). An **owner** signs in (Google/Apple), creates a time-limited **Demo** (free, 10 min, 1 feedback) or **Premium** (1 credit → 24 h, multi-responder) link, and shares it. **Anonymous responders** open `/f/<code>` and leave feedback on a static public page. **AI** summarizes the *real* feedback (never fabricates). Project: `feedbacktome-79655` (`.firebaserc:4`); app `1.0.3+20` (`pubspec.yaml:19`).

**Two mutually-exclusive backends** (compile-time XOR, no runtime failover): **Firestore** (default) or **Railway REST** (opt-in via `USE_RAILWAY_API`) — `lib/app_state.dart:22-23`, `lib/config/backend_config.dart:28-29`.

## Components (by layer)

- **Clients** — Flutter iOS (`com.anlgzl.feedback2meapp`), Flutter Android (`app.feedbacktome`), anonymous Responder Browser. *(Flutter Web build source exists in `web/` but is NOT served — `firebase.json:16`.)*
- **Entry / Access** — Firebase Hosting (serves `web_static/`, rewrites `/f`,`/f/**`→`f.html`, `firebase.json:15-57`); `f.html` public page; Flutter gates `_AppLaunchGate`/`_MinVersionGate`/`_AuthGate` (`lib/main.dart:364-546`).
- **Application / Business** — `AppDataBackend` seam, `FirestoreService`, `RailwayApiService`, `ReportService`, `OpenAiAudienceClient`, `IapService`, `VersionGate`, `FeedbackFormScreen`.
- **Data / Security / Backend** — Firebase Auth (Google/Apple), **Firestore Rules** (security boundary), Cloud Firestore, Cloud Function `iapVerify`, Railway API (Fastify+Prisma), `/ai/chat` proxy, PostgreSQL.
- **External** — OpenAI (`gpt-4o-mini`), Apple App Store, Google Play.
- **Release / Operations** (separate plane) — Codemagic, GitHub Actions, Firebase Deploy, Railway Deploy, App Store Connect, Google Play Console.

## Runtime architecture

Owner app: `main()` → `_AppLaunchGate` router (`lib/main.dart:395`). If a deeplink `/f/<code>` is present → **public** `FeedbackFormScreen`, **bypassing onboarding/auth/min-version gate** (`lib/main.dart:398-408`). Otherwise → `_MinVersionGate` (owner-only, fail-open) → `_AuthGate` (Firebase auth) → `LandingScreen`. See [`diagrams/01-owner-flow.mmd`](./diagrams/01-owner-flow.mmd).

## Data architecture

Two **separate persistence domains** (never both live in one build):
- **Firestore (default)** — collections `users`, `links`, `feedbacks`, `appConfig/version`, `processedPurchases`, `users/{uid}/audienceScoreSnapshots` (+ `reportBody/full`). 4 composite indexes (`firestore.indexes.json`). Field/rule map: `component-inventory.json`.
- **PostgreSQL (opt-in, Railway)** — Prisma models `User`, `OAuthAccount`, `Link`, `Feedback`, `AudienceScoreSnapshot`, `AudienceReportBody` (`server/prisma/schema.prisma:12-112`).

Link **lifecycle is server-authoritative** off `createdAt` (serverTimestamp) + tier duration, NOT client `validUntil` (display-only): `firestore.rules:22-70`, `lib/models/feedback_link.dart:106-121`.

## Security architecture

- **Firestore Rules are the client↔Firestore boundary** — evaluated on every client read/write (`firestore.rules`). They enforce: createdAt window (transitional ±2 min, TODO strict, `:44-48`), atomic demo single-use via `get()/getAfter()` (`:61-70`), credit/demo entitlement burn on create (`:83-98`), owner immutability / no reactivation (`:104-121`), `appConfig/version` public-read / write-locked — narrowed to the single `version` doc so other `appConfig` docs stay private (`:145-155`), `processedPurchases` fully client-locked (`:139-141`).
- **Admin SDK bypasses rules** — the `iapVerify` Cloud Function writes `users.paidLinkCredits` + `processedPurchases` with Admin privileges (`functions/src/index.ts:174,185-193`).
- **Railway API is a parallel, independent security domain** — Admin-level Postgres creds via Prisma; security is enforced in app code (zod schemas, ownership `where`, JWT `authenticate`), NOT by Firestore rules (`server/src/index.ts:51-57`, `server/src/routes/users.ts:5-8`). CORS is fully open (`server/src/index.ts:42-45`).
- **Auth** — Firebase Auth Google + Apple only; no anonymous / email-password (`lib/services/auth_service.dart:55-98`). Public feedback is unauthenticated by design.

## Backend architecture

- **Firebase Functions** — one function, `iapVerify` (onCall, `us-central1`): verifies Apple (`buy.itunes.apple.com/verifyReceipt`, sandbox fallback) and Google (`androidpublisher/v3`) receipts, grants `paidLinkCredits` idempotently (`processedPurchases/{platform:txId}` dedupe) — `functions/src/index.ts:119-199`.
- **Railway API (Fastify+Prisma)** — routes `health`, `auth` (dev-login bridge only — real OAuth is a TODO, `server/src/routes/auth.ts:10-13`), `users`, `links`, `feedbacks`, `snapshots`, `ai`. JWT guards owner routes; `/health`, `/public/links/by-code/:code`, `/feedbacks`, `/ai/chat` are public (`server/src/index.ts:59-65`). See [`diagrams/05-backend-data-flow.mmd`](./diagrams/05-backend-data-flow.mmd).

## AI architecture

OpenAI is **called server-side only**, never from the client. `OpenAiAudienceClient` POSTs to `AI_PROXY_URL` (`/ai/chat`) with no key (`lib/services/openai_audience_client.dart:23,654`); the Railway `ai.ts` route holds `OPENAI_API_KEY` and calls `api.openai.com/v1/chat/completions`, model `gpt-4o-mini`, whitelisted fields, IP-rate-limited 40/min (`server/src/routes/ai.ts:3,18-69`). AI **summarizes/groups real feedback** — it does not generate feedback. If `AI_PROXY_URL` is unset or the proxy 503s (no key), the client falls back to local heuristics (`lib/services/report_service.dart:1086`). See [`diagrams/04-ai-report-flow.mmd`](./diagrams/04-ai-report-flow.mmd).

## IAP architecture

`in_app_purchase`, one consumable `premium_link_single` = 1 credit (`lib/config/iap_products.dart:27`, `functions/src/iap-core.ts:11`). **Server-authoritative** flow (restored): purchase → `IapService.verifyAndGrant` → `httpsCallable('iapVerify')` Cloud Function → Apple/Google receipt verify → idempotent Admin-SDK credit grant. The client writes **no** credit. Transient verify failure keeps the purchase queued for an idempotent retry; permanent rejection completes without credit. Covered by `test/iap_service_test.dart` (client) + `functions/test/iap-core.test.mjs` (server, incl. concurrency) via the `ci-functions-iap` invariant. Real store sandbox E2E is still pending (`syn-iap-verify`, not-configured). See [`diagrams/03-premium-iap-flow.mmd`](./diagrams/03-premium-iap-flow.mmd).

## Public feedback architecture

Browser → Hosting rewrite → `web_static/f.html` (no-cache). `getCode()` parses the code; `resolvePublicApiBase()` decides persistence: **default = Firestore direct** (query `links`, batch-write `feedbacks` + demo close), **opt-in = Railway REST** if `<meta name="ftm-public-api">`/`window.FTM_PUBLIC_API_BASE` is set (`web_static/f.html:342-350,549-644`). A `localStorage` marker `feedback2me_submitted_<linkId>` is a **UX deterrent, not security** (`web_static/f.html:503-527`). Public feedback is **anonymous** (no Firebase Auth) and **not affected by the min-version gate**. See [`diagrams/02-public-feedback-flow.mmd`](./diagrams/02-public-feedback-flow.mmd).

## Release architecture

Build/deploy is a **separate plane** from runtime traffic:
- **iOS** → Codemagic `flutter build ipa` → App Store Connect / TestFlight (`codemagic.yaml:64-91`, Apple ID `6762295382`).
- **Android** → `app.feedbacktome`; **no automated Play publish workflow in repo** (manual).
- **Firebase** → `firebase deploy --only hosting|functions|firestore:rules` (`firebase.json:2-16`).
- **Railway** → `server/Dockerfile` (Node API) and a **separate** root `Dockerfile` (Flutter web static via `serve`).
- **CI** → GitHub Actions `server-concurrency-test.yml` runs the REST demo single-comment invariant on a disposable Postgres 16 (`.github/workflows/server-concurrency-test.yml`).
See [`diagrams/06-release-pipeline.mmd`](./diagrams/06-release-pipeline.mmd).

## Legacy-client architecture

The **min-version gate manages only gate-aware (Release A+) clients** — they read `appConfig/version.minSupportedBuild` and force-update if below (`lib/services/version_gate.dart`). **Pre-gate legacy clients never read `appConfig`** and cannot be remotely force-updated; they are only made "unsupported" by the future strict `createdAt == request.time` cutover (their link-create then returns permission-denied). The transitional ±2 min createdAt window keeps old + new clients working meanwhile (`firestore.rules:44-48`). See journey `j-legacy-cutover`.

## Known fallback paths

- Backend selection is **compile-time XOR**, not a runtime failover (default Firestore).
- Public feedback: Firestore direct (default) ↔ Railway REST (opt-in meta tag).
- AI: proxy → **heuristic** fallback when `AI_PROXY_URL` unset or proxy 503.
- Summary caching: expired-link summaries served from SharedPreferences.
- Min-version gate: **fail-open** on read error.

## Single points of failure & known issues

- **Cloud Firestore + Firestore Rules** — the default runtime's data + security core; an outage or a rules misconfig blocks all owner + public writes.
- **Firebase Hosting / `f.html`** — the entire public feedback funnel.
- **Railway API** (only in REST-mode builds) — its Postgres is a separate SPOF for that configuration.
- **IAP credit-grant (server verification RESTORED):** `IapService` no longer writes credit client-side. On a successful purchase it calls the `iapVerify` Cloud Function (`httpsCallable`), which verifies the Apple/Google receipt and grants `paidLinkCredits` idempotently via the Admin SDK. The committed `firestore.rules` `noPrivilegeEscalation` (`firestore.rules:116-121`) still rejects any client credit increase — now consistent with the client, which writes none. Covered at the code level by `test/iap_service_test.dart` + `functions/test/iap-core.test.mjs` (`ci-functions-iap`). **Remaining P1:** a real App Store / Play sandbox purchase E2E has not been run (`syn-iap-verify`, not-configured) — security architecture is fixed, but the live store round-trip is still unverified.

## Future observability integration

Every node has a stable `node-*` id and every edge an `e-*`/`r-*` id (see the JSON files and the interactive HTML `data-id`). A health layer can later map each `node-*` to `healthy | degraded | down | unknown` and re-color the same diagram — no re-modeling required. Current state everywhere = **UNKNOWN / NOT MONITORED**.
