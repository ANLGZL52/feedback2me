# Feedback2Me Operational Status

Generated: 2026-08-19T14:14:02.930Z  ·  window: 24h  ·  events: 0

- **Observability Platform:** PARTIAL
- **Runtime Validation:** PARTIAL
- **Product Release Gate:** WARN
- **Current Runtime:** HEALTHY

## Domains
- **IAP**: IDLE — verify 0 (ok 0/fail 0), grants 0, replays 0, p95 —ms
- **OpenAI**: IDLE — req 0, fail 0, p95 —ms
- **Railway**: IDLE — req 0 (5xx 0)
- **Postgres**: HEALTHY — HEALTHY
- **Collector**: UNKNOWN — last — (— min)

## Active Alerts
- [WARNING] COLLECTOR/COLLECTOR_RUN_FAILED — collector run did not complete successfully (ONGOING)
- [WARNING] VALIDATION/IAP_E2E_VALIDATION_DEFERRED — real TestFlight sandbox IAP purchase not yet performed (DEFERRED — not fabricated) (NEW)

## Resolved
- RELEASE/MISSING_IAP_E2E_EVIDENCE (duration 0 min)

## Deferred Validation
- **REAL_IAP_TESTFLIGHT_E2E** — Status: DEFERRED · Reason: PHYSICAL_DEVICE_TEST_CURRENTLY_UNAVAILABLE · required for product release (NOT verified — do not claim as passed)

## Validation Evidence
- Real IAP TestFlight E2E: **DEFERRED** (PHYSICAL_DEVICE_TEST_CURRENTLY_UNAVAILABLE)
- Synthetic IAP contract (fixtures, NOT real StoreKit): **VERIFIED**
- Deploy: commit d2471fc · build 22 · fn —
