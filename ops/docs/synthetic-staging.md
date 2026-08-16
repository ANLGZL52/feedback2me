# Synthetic Staging Monitoring — Design (NOT configured)

The components/journeys that live read-only checks cannot cover (Firebase Auth, Cloud
Function iapVerify, OpenAI, demo/premium create, feedback submit) require **synthetic
staging** checks that actually exercise the flow. This turn only DESIGNS them. Every one
reports **NOT_CONFIGURED** until a real staging environment exists — **no fake PASS**
(Phase 6/40), and **never against production data** (Phase 7/41).

## Hard rules

- **No production account, no production Firestore/Postgres write, no real purchase.**
- Synthetic runs use a **dedicated staging environment** and **dedicated test identities**.
- Status stays `NOT_CONFIGURED` until the environment below is provisioned and wired.

## Required environments (report to user — Phase 7)

| Need | For |
|---|---|
| Staging Firebase project (separate from `feedbacktome-79655`) with the same rules deployed | demo/premium create, feedback, atomic demo, appConfig |
| Dedicated **test Google + Apple accounts** (staging) | Firebase Auth synthetic |
| Staging Railway API + staging Postgres | REST path, AI proxy |
| `OPENAI_API_KEY` on the staging server (token budget) | AI summary synthetic |
| Apple/Google **sandbox** IAP + staging Functions with the **intended `iapVerify` restored** | IAP verify synthetic (blocked today by the P0 gap) |
| A staging credit-grant path (Admin) | premium create synthetic |

## Synthetic checks (matrix: `syn-*`, all `not-configured`)

| id | Journey | What it would do (staging only) |
|---|---|---|
| `syn-auth` | owner-start | Sign in a TEST account (Google/Apple); confirm uid + owner home reached. |
| `syn-create-demo` | create-demo | Create a demo link as the test user; verify 10 min window + `freeDemoLinkUsed` consumed. |
| `syn-demo-feedback-close` | public-feedback | Submit first demo feedback; verify atomic close + second submit denied. |
| `syn-create-premium` | create-premium | With a staging credit, create premium; verify 24h + credit −1. |
| `syn-premium-multi` | create-premium | Multiple different-responder feedbacks accepted for 24h. |
| `syn-ai-summary` | ai-summary | Tiny fixed prompt to staging `/ai/chat`; verify parse. Minimal tokens. |
| `syn-iap-verify` | purchase-credit | Sandbox purchase → `iapVerify` → credit grant, idempotent. **Requires the P0 IAP gap fixed first.** |

## Why "endpoint reachable" ≠ "journey healthy" (Phase 8-10)

- **Firebase Auth**: the identitytoolkit endpoint is always up (Google infra). That says nothing
  about whether *this app's* Google/Apple OAuth config works. Only `syn-auth` proves the journey.
  → owner-start stays **UNKNOWN** live.
- **OpenAI / /ai/chat**: a GET to the Railway host proves the host is up, not that OpenAI answers.
  A real POST spends tokens / has side effects → not production-safe. → ai-summary **UNKNOWN** live
  (soft dep; heuristic fallback keeps it working anyway).
- **Cloud Function iapVerify**: the function existing ≠ receipts verifying. onCall needs auth + a
  receipt; not safely invokable. → purchase-credit stays **DEGRADED/UNKNOWN**, and the **static P0
  gap** (client-direct credit) keeps it a release blocker regardless.

## Release impact

Because these are release-critical journeys, `NOT_CONFIGURED` → the journey is **UNKNOWN** →
the release gate BLOCKS with a P1 `unverified-*` blocker (Phase 13). This is intentional: you
cannot mark a build READY on journeys you have never verified. Once staging is wired, the
`syn-*` checks flip these from UNKNOWN to HEALTHY/DOWN based on real runs.
