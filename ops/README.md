# Feedback2Me — Ops / Control Plane

App-independent **observability + release gate** built on top of the architecture map
(`docs/architecture/*.json`). It answers "is the system running right now?" — not just
"how is it wired?". **Read-only. No production writes. No deploys.** It does not depend on
the Feedback2Me app and can run while the app is down.

> **Local dashboard port = 8090 (NOT 8080).** Serve the repo root and open the dashboard:
> `python -m http.server 8090 --bind 127.0.0.1` → http://localhost:8090/ops/dashboard/index.html
> Do **not** use 8080: the Firestore emulator (`firebase.json` → `emulators.firestore.port`)
> binds 8080, so a dashboard server there collides with `firebase emulators:exec` and makes
> `ci-rules-emulator` / `ci-functions-iap` fail to bind. Keep the dashboard on 8090.

## Layout

```
ops/
  checks/
    check-matrix.json      # what to check per component (prod-safe/read-only/type/impl)
    health-policy.json     # path-based journey deps, fallback/XOR, thresholds, static risks, release gate
  schemas/
    health-event.schema.json     # one check result (operational metadata only — no PII/secrets)
    health-snapshot.schema.json  # ops-status/latest.json shape
  monitor/
    engine.mjs             # PURE health engine (edge/journey propagation, incidents, release gate)
    engine.test.mjs        # 15 unit tests (propagation, fallback, thresholds, gate)
    run.mjs                # runner: read-only checks -> engine -> ops-status/latest.json + JSONL
    preflight.mjs          # release gate CLI (exit 1 if P0 blocker)
    checks/*.mjs           # check adapters (http-get, firestore-appconfig, github-actions, arch-drift)
  dashboard/index.html     # live control plane (Architecture / Live Health / Journeys / Incidents / Release)
  fixtures/simulation-health.json  # failure-injection presets for the dashboard
  runbooks/*.md            # per-component operator runbooks
  docs/observability-architecture.md
ops-status/latest.json     # merged current snapshot the dashboard reads (regenerated each run)
```

## Run

```bash
node ops/monitor/run.mjs        # run read-only prod checks -> ops-status/latest.json
node --test ops/monitor/        # engine self-tests (15)
node ops/monitor/preflight.mjs  # release gate (exit 0 ready / 1 blocked)
# dashboard: serve repo root then open /ops/dashboard/index.html
python -m http.server 8123      # (from repo root)
```

## Source of truth

`ARCHITECTURE (what)` = `docs/architecture/{component-inventory,dependency-graph,user-journeys}.json`
`+ CURRENT HEALTH (how it runs now)` = `ops-status/latest.json`
`= LIVE SYSTEM MAP` (the dashboard merges them).

## Principles

- **No fake health.** No real check => `UNKNOWN` (never green-washed).
- **Path-based, fallback-aware.** Firebase Auth down ≠ whole app down; it fails owner/create journeys but not public feedback. Firestore down with Railway up => public feedback DEGRADED (fallback), not DOWN.
- **Production-safe only (this turn).** Live checks are read-only GETs (hosting/f.html reachability, public appConfig read, Railway `/health`, GitHub Actions last run). Synthetic staging writes (create demo, submit feedback, purchase) are defined in the matrix but NOT run against production.
- **PII/secret policy.** Events carry operational metadata only — never feedback text, names, emails, tokens, JWTs, receipts, keys, `X-Dev-Secret`. See `schemas/health-event.schema.json` and `run.mjs` `safeDetails()`.
- **Static architecture risks** (e.g. the IAP client-direct credit gap) surface as permanent badges and P0 release blockers, independent of live checks. **Not fixed here.**
- **Monitoring independence.** Not hosted on Firebase/Railway (same failure domain). First iteration: GitHub Actions (`.github/workflows/ops-health.yml`) scheduled + manual; vendor-neutral so an external runner can be added later.

## What is actually live vs pending

| Live read-only checks | Result source |
|---|---|
| Firebase Hosting reachable | HTTP GET |
| f.html reachable | HTTP GET |
| Firestore reachable | Firestore REST (public appConfig read) |
| appConfig public-read rule / version gate | Firestore REST (403 => rule not deployed) |
| Railway API `/health` | HTTP GET |
| GitHub Actions last run | `gh` CLI |
| Architecture drift | JSON self-consistency |

`UNKNOWN` (no safe live check yet): Firebase Auth, Cloud Function iapVerify, OpenAI, PostgreSQL (via Railway), Apple/Google stores, Codemagic. These need synthetic-staging checks (a TEST account / staging DB) — future work.
