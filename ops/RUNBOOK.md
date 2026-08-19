# Feedback2Me — Operational Runbook (Observability V3)

Action-oriented response for each CRITICAL alert emitted by
`ops/monitor/evaluate-runtime.mjs` (artifact: `ops-status/runtime-health.json`).
Thresholds live in `ops/observability-slo.json`. **No secrets/PII in logs or here.**

General rules:
- The evaluator is READ-ONLY. It never mutates Firestore, credits, or production.
- `NO_TRAFFIC` (IDLE) is healthy. `NO_OBSERVABILITY` (UNKNOWN) means the collector
  could not see the system — treat as "we are blind", not "all good".
- Never fabricate purchase/credit evidence. Never hand-edit `processedPurchases`
  or `paidLinkCredits`.

---

## IAP_E2E_VALIDATION_DEFERRED  (NOT an incident)
**What it means:** the real physical-device TestFlight/Sandbox purchase of
`premium_link_single_v2` has not yet been performed, so we have no REAL StoreKit
end-to-end evidence. This is a **deferred validation**, not an outage or a defect.
It is WARNING severity and **non-blocking** at the current TestFlight stage.
**What IS still proven (do claim):** the observability *platform* is built and
operational (`observabilityPlatformStatus=FULL` in CI); the IAP contract is proven
by deterministic SYNTHETIC fixtures (started→apple.success→credit.granted +1;
replay +0; all money-safety invariants); iapVerify is LIVE, server-authoritative,
idempotent, Android fail-closed.
**What is NOT proven (do NOT claim):** a real charged Apple sandbox transaction
flowing through iapVerify→processedPurchases→`paidLinkCredits +1`. Do NOT state
"IAP E2E PASS", and never fabricate `iap.verify.apple.success`, `iap.credit.granted`,
`processedPurchases`, receipts, or a `+1` credit.
**How to complete it later (no system redesign):** perform TestFlight 1.0.4(22) →
Premium → one sandbox purchase; capture the real result into
`ops-status/iap-e2e-evidence.json` `{ "verified": true, "source": "testflight-sandbox", ... }`.
On the next evaluation the registry flips `REAL_IAP_TESTFLIGHT_E2E` DEFERRED→VERIFIED,
`runtimeValidationStatus` recomputes to FULL, and the deferred WARN clears — with NO
evaluator/architecture change.
**Escalation:** none — this is tracked work, not an incident.

---

## IAP_CREDIT_INVARIANT_BREACH  (IAP_MONEY_SAFETY_BREACH + IAP_GRANT_DELTA_NOT_ONE / IAP_REPLAY_DELTA_NOT_ZERO / IAP_CREDIT_UNKNOWN_PRODUCT / IAP_CREDIT_AFTER_FAILURE / IAP_DUPLICATE_GRANT / IAP_SUCCESS_WITHOUT_CREDIT)
**What it means:** the money ledger is inconsistent — a credit was granted with the
wrong amount, for an unknown product, after a failed verification, more than once
for one store transaction, or a verified purchase did not result in a committed credit.
**How to verify:** open `runtime-health.json` → `alerts[]` evidence (safe correlation
id / txCorrelation hash / productId — never the raw receipt). Cross-check the
iapVerify Cloud Logging entries for that `clientRequestId`. Confirm the
`processedPurchases` doc count vs `paidLinkCredits` for the affected user via the
Firebase console (read-only).
**First safe action:** confirm it is real (not a collection-window artifact — see
IAP_SUCCESS_WITHOUT_CREDIT note). If real, freeze the release (gate already BLOCKs).
**What NOT to do:** do NOT hand-edit credits or processedPurchases; do NOT retire
`premium_link_single`; do NOT deploy rule changes reactively.
**Rollback/mitigation:** the grant path is server-authoritative + idempotent
(`functions/src/iap-core.ts grantCredit`). If a code regression caused it, revert the
offending iapVerify change and redeploy ONLY `iapVerify`.
**Escalation:** any confirmed duplicate/over-grant → owner immediately; it is
release-blocking and money-affecting.

> IAP_SUCCESS_WITHOUT_CREDIT caveat: verify + grant are emitted in the same request,
> so a genuine breach shows both-or-neither within one window. If only `success` was
> collected (window truncation / 500-line cap), re-run the collector and re-evaluate
> before declaring an incident.

## IAP_VERIFY_DOWN
**What it means:** the `iapVerify` callable is unreachable — new purchases cannot be
verified, so credits are not granted (users may be charged with no credit).
**How to verify:** `curl -s -XPOST https://us-central1-feedbacktome-79655.cloudfunctions.net/iapVerify -H 'Content-Type: application/json' -d '{"data":{}}'` should return `401 UNAUTHENTICATED`. Anything else (timeout / 5xx) = down.
**First safe action:** check Firebase Functions status + recent deploy. Confirm
`APPLE_SHARED_SECRET` still bound.
**What NOT to do:** do NOT grant credits manually to affected users.
**Rollback/mitigation:** redeploy ONLY `iapVerify` from the last-good commit
(`firebase deploy --only functions:iapVerify`). in_app_purchase keeps unverified
purchases queued, so a fixed function re-verifies them (no loss).
**Escalation:** owner — this is CRITICAL + release-blocking.

## APPLE_VERIFICATION_FAILURE_SPIKE  (IAP_VERIFY_FAILURE_ELEVATED / IAP_TRANSIENT_FAILURE_SUSTAINED / IAP_REJECTED_SPIKE)
**What it means:** Apple is rejecting receipts (permanent) or failing transiently
(shared-secret/outage) at an elevated rate.
**How to verify:** inspect `iap.verify.apple.rejected/transient_failure` counts +
`errorCode` (e.g. `apple_status_21004` = shared-secret mismatch → config).
**First safe action:** for transient/21004, verify `APPLE_SHARED_SECRET`. For a
permanent-reject spike, check whether a product/receipt-format change shipped.
**What NOT to do:** do not disable verification to "fix" the rate.
**Rollback/mitigation:** fix the secret/config; transient failures self-heal (client
retries). **Escalation:** sustained CRITICAL rate → owner.

## OPENAI_PROVIDER_FAILURE  (OPENAI_DEGRADED / OPENAI_LATENCY_DEGRADED / OPENAI_TOKEN_SPIKE)
**What it means:** the aiSummary→OpenAI path is failing, slow, or unusually
expensive (token spike).
**How to verify:** `openai.request.failed/timeout/rate_limited` counts + p95 latency +
avg tokens in the artifact.
**First safe action:** confirm it is provider-side (rate limit / outage) vs a prompt
regression. Feature is non-critical — the app degrades gracefully.
**What NOT to do:** do not log prompt/completion content while investigating.
**Rollback/mitigation:** if a prompt/model change caused a token spike, revert it and
redeploy ONLY `aiSummary`. **Escalation:** sustained CRITICAL only.

## POSTGRES_UNAVAILABLE  (POSTGRES_CRITICAL / POSTGRES_WARNING)
**What it means:** the low-privilege Postgres health probe failed (1=WARNING, 3
consecutive=CRITICAL).
**How to verify:** check Railway Postgres status; the probe never reads business data.
**First safe action:** confirm DB reachability + connection limits.
**What NOT to do:** do not log rows/credentials.
**Rollback/mitigation:** restart/scale the DB in Railway; confirm `OPS_POSTGRES_DATABASE_URL` (ops-health role) is valid. **Escalation:** CRITICAL → owner.

## RAILWAY_UNAVAILABLE  (RAILWAY_5XX_ELEVATED / RAILWAY_UNREACHABLE)
**What it means:** the Railway API is returning 5xx at an elevated rate, or the
collector could not reach Railway (UNREACHABLE ≠ confirmed outage).
**How to verify:** Railway httpLogs (authoritative) 5xx count/rate in the artifact.
`0 requests` = NO_TRAFFIC, not failure.
**First safe action:** check the latest Railway deployment/logs.
**Rollback/mitigation:** roll back the Railway deployment if a deploy regressed it.
**Escalation:** CRITICAL 5xx rate → owner.

## GCP_WIF_AUTH_FAILED  (surfaces as COLLECTOR_RUN_FAILED / domain UNKNOWN)
**What it means:** the collector's short-lived WIF token could not read Cloud Logging
(`GCP_PERMISSION_DENIED`). This is a **collector-auth** problem, NOT a Cloud Function
outage — the app may be perfectly healthy.
**How to verify:** ops-health workflow logs — WIF step + `gcp-functions-logs.mjs`
returned `GCP_PERMISSION_DENIED`.
**First safe action:** re-check the WIF provider/service-account binding + the
`logging.read` scope. Do NOT assume the app is down.
**What NOT to do:** do not widen the GCP identity's privileges beyond read-only logging.
**Escalation:** persistent → owner; classify as NO_OBSERVABILITY, not RUNTIME UNHEALTHY.

## COLLECTOR_STALE
**What it means:** no fresh runtime collection within `slo.collector.staleMinutes`
(~95 min ≈ 3 missed 30-min runs). We are flying blind.
**How to verify:** `runtime-health.json` → `domains.COLLECTOR.metrics.ageMinutes`;
check the ops-health workflow run history.
**First safe action:** confirm the scheduled GitHub Action is running (not disabled /
not failing at the collect step). **What NOT to do:** don't silence the alert by
widening the window. **Escalation:** release-blocking; owner if the schedule is broken.

## SECRET_OR_PII_LEAK_DETECTED  (SECRET_OR_PII_LEAK)
**What it means:** the collector's own scan matched a secret/PII pattern in a
collected event — a normalizer allow-list regression.
**How to verify:** identify the offending event shape (NOT its value) and the
normalizer that let it through (`ops/monitor/checks/*.mjs`).
**First safe action:** treat as CRITICAL + release-blocking. Purge the affected
`ops-status/runtime-events/*.jsonl` line; do NOT commit it.
**What NOT to do:** do NOT paste the leaked value anywhere (issue, PR, chat, here).
**Rollback/mitigation:** fix the emitter/normalizer allow-list; add a test proving the
field is dropped. **Escalation:** owner immediately; rotate any exposed credential.
