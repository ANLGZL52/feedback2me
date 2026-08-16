# Feedback2Me — Observability / Control Plane Architecture

## Goal

Turn the static architecture map into a **live control plane** that answers:
Firebase/Railway/OpenAI up? Firestore Rules behaving? Public feedback / owner login /
demo create / premium create / AI summary / IAP working? Which component is down and
**which journeys does that break**? First failure? Last good? Release-ready for iOS/Android?

## Planes

- **Runtime plane** (observed): the 41-component architecture from `docs/architecture`.
- **Ops / control plane** (observer): `ops/` — check runner, health engine, incident engine,
  release gate, dashboard, status store. It observes the runtime **from outside** and must keep
  working when the runtime is down. It is therefore NOT hosted on Firebase Hosting or Railway
  (same failure domain); it runs on CI (GitHub Actions) / any external runner.

## Data flow

```
check-matrix.json ── run.mjs ──► check adapters (read-only) ──► raw results
                          │
                          ▼
        engine.mjs: applyCheckResult (thresholds) ──► component health
                          │         reconcileIncidents ──► incidents
                          ▼
        health-policy.json ──► journeyStatus (path-based, fallback-aware) ──► journey health
                          │         computeOverall (critical journeys) ──► overall
                          ▼
                 ops-status/latest.json  ◄── dashboard merges with docs/architecture/*.json
                          │
                          ▼
                 preflight.mjs ──► release gate (P0/P1/P2) ──► GO / NO-GO (exit 0/1)
```

## Health model

- Status set: `HEALTHY | DEGRADED | DOWN | UNKNOWN | CHECKING`.
- **Component health** = threshold-smoothed check result: 1 failure → DEGRADED, 2 consecutive → DOWN;
  2 consecutive successes → HEALTHY; P0 invariant → immediate DOWN. UNKNOWN never fabricates health.
- **Edge health** = derived from endpoints (DOWN if either down; DEGRADED if either degraded; UNKNOWN if either unknown).
- **Journey health** = path-based over `health-policy.json`: a journey is DOWN only if a *hard*
  dependency with no working fallback is DOWN; a *fallback group* whose primary is down but an
  alternate is up → DEGRADED; a *soft* dependency down → DEGRADED (not DOWN). Static risks (IAP)
  cap a journey's best status.
- **Overall** = worst of the critical journeys (owner-start, create-demo, create-premium, public-feedback):
  any DOWN → CRITICAL, any DEGRADED → DEGRADED, all HEALTHY → HEALTHY, else UNKNOWN.

## Why path-based (not global)

"one dependency down = whole app down" is wrong here. Two backends are XOR (Firestore default vs
Railway); public feedback is anonymous and independent of Firebase Auth; AI degrades to a heuristic
fallback. The engine models these so an operator sees *which flow* actually broke.

## Failure propagation examples (verified by engine.test.mjs)

| Down | Effect |
|---|---|
| Firebase Auth | owner-start / create-demo / create-premium DOWN · public-feedback HEALTHY |
| Firestore (Railway up) | public-feedback DEGRADED (fallback) · owner create DOWN |
| PostgreSQL (Firestore default) | public-feedback HEALTHY · REST journey DOWN (non-critical) |
| OpenAI / AI proxy | ai-summary DEGRADED (heuristic) · overall unaffected |
| Hosting | public-feedback DOWN (entire public funnel) |

## Release gate

`preflight.mjs` blocks (P0) on: any P0 static risk (**IAP client-direct credit gap**), any required
CI invariant not `PASS`, any required live-critical journey DOWN. P1 → manual; P2 → warning.
The IAP gap is a **permanent P0 blocker until iapVerify is wired** — it makes the release NOT READY
by design so it can't be shipped unnoticed. (The gap is reported, not fixed here.)

## Logs, history, incidents

Events are JSONL (`ops-status/events/<date>.jsonl`), operational-metadata-only. To avoid repo bloat,
CI uploads them as **artifacts** rather than committing every run; `latest.json` is the single
committed snapshot. Incidents open on DOWN/DEGRADED transitions and resolve on recovery, carrying
firstBad/lastBad/lastGood + release/build for deploy-correlation.

## Roadmap to fully-live monitoring

1. Wire CI invariant evidence (`ops-status/ci-evidence.json`) from the existing Flutter/rules/server/web
   test jobs so the release gate reflects real LAST-VERIFIED results.
2. Add synthetic-staging checks (TEST account + staging DB) for Firebase Auth, demo/premium create,
   AI summary, IAP verify — never against production user data.
3. Add an external (non-Firebase/Railway) scheduled runner for true failure-domain independence.
4. Persist history to an ops store (artifact retention or a small external bucket) for trends.
