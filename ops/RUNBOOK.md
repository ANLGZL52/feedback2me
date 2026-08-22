# Feedback2Me — Operational Runbook (Observability V3)

Action-oriented response for each CRITICAL alert emitted by
`ops/monitor/evaluate-runtime.mjs` (artifact: `ops-status/runtime-health.json`).
Thresholds live in `ops/observability-slo.json`. **No secrets/PII in logs or here.**

**Incident code → runbook section** (V4 incident delivery links every CRITICAL to a
section here via `RUNBOOK_SECTIONS` in `ops/monitor/incident-delivery.mjs`):

| Alert code(s) | Section |
|---|---|
| `IAP_VERIFY_DOWN` | IAP_VERIFY_DOWN |
| `IAP_MONEY_SAFETY_BREACH`, `IAP_GRANT_DELTA_NOT_ONE`, `IAP_REPLAY_DELTA_NOT_ZERO`, `IAP_CREDIT_UNKNOWN_PRODUCT`, `IAP_CREDIT_AFTER_FAILURE`, `IAP_DUPLICATE_GRANT`, `IAP_SUCCESS_WITHOUT_CREDIT` | IAP_CREDIT_INVARIANT_BREACH |
| `IAP_VERIFY_FAILURE_ELEVATED`, `IAP_TRANSIENT_FAILURE_SUSTAINED`, `IAP_REJECTED_SPIKE` | APPLE_VERIFICATION_FAILURE_SPIKE |
| `OPENAI_DEGRADED`, `OPENAI_LATENCY_DEGRADED` | OPENAI_PROVIDER_FAILURE |
| `POSTGRES_CRITICAL` | POSTGRES_UNAVAILABLE |
| `RAILWAY_5XX_ELEVATED`, `RAILWAY_UNREACHABLE` | RAILWAY_UNAVAILABLE |
| `COLLECTOR_STALE` | COLLECTOR_STALE |
| `COLLECTOR_RUN_FAILED` | GCP_WIF_AUTH_FAILED |
| `SECRET_OR_PII_LEAK` | SECRET_OR_PII_LEAK_DETECTED |
| `SERVICE_COMPONENT_DOWN` | SERVICE_COMPONENT_DOWN |

Incident delivery is **LIVE** since V6 (`OPS_INCIDENT_DELIVERY_ENABLED=true`,
`OPS_ALERT_DRY_RUN=false`) — the V5 pipeline (`incident-delivery.mjs`) is the ONE
canonical production GitHub-Issue writer (the legacy `alert.mjs` writer is retired).
WARNING alerts never create incidents (artifact/report only); only NEW CRITICAL alerts
do. See the V6 operational runbook at the end for delivery-subsystem failures.

---

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

## IAP_CREDIT_INVARIANT_BREACH  (IAP_MONEY_SAFETY_BREACH + IAP_GRANT_DELTA_NOT_ONE / IAP_REPLAY_DELTA_NOT_ZERO / IAP_CREDIT_UNKNOWN_PRODUCT / IAP_INVALID_PRODUCT_CREDITED / IAP_CREDIT_AFTER_FAILURE / IAP_DUPLICATE_GRANT / IAP_SUCCESS_WITHOUT_CREDIT)
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

## IAP_VERIFY_DOWN  (IAP_VERIFY_DOWN / IAP_LATENCY_DEGRADED)
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
**What it means:** a store (Apple or Google Play) is rejecting receipts (permanent)
or failing transiently (shared-secret/service-account/outage) at an elevated rate.
**How to verify:** inspect `iap.verify.{apple,android}.rejected/transient_failure`
counts + `errorCode` (e.g. `apple_status_21004` = Apple shared-secret mismatch;
`play_http_401`/`play_http_403` = Play service-account not authorized → config).
**First safe action:** for Apple transient/21004, verify `APPLE_SHARED_SECRET`; for
`play_http_401/403`, verify the Play service account is linked + granted in Play
Console and `PLAY_SERVICE_ACCOUNT_JSON` is current. For a permanent-reject spike,
check whether a product/receipt-format change shipped.
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

---

## SERVICE_COMPONENT_DOWN  (CRITICAL, release-blocking)
**What it means:** a live monitored component reported status `DOWN` in the
component snapshot (`ops-status/latest.json`). Ported from the retired legacy
`alert.mjs` writer — this now flows through the canonical V5 incident pipeline.
**How to verify:** open `ops-status/latest.json`, find components whose `status` is
`DOWN` (the alert message lists the ids). Confirm it is a real reachability failure,
not `UNKNOWN` (no evidence) or `DEGRADED` (dashboard-only, never pages).
**First safe action:** check the named component's own health/runbook (Firebase
reachability, backend, etc.). The incident issue is auto-managed (open/update/close).
**What NOT to do:** do NOT hand-create a separate issue; the V5 pipeline owns it.
**Rollback/mitigation:** restore the component; the incident auto-resolves after the
stability window. **Escalation:** owner if a user-facing journey is affected.

---

## V6 operational / delivery-subsystem runbook

These describe failures of the MONITORING system itself. Golden rule: a monitoring or
delivery failure is NOT a product outage, and incident-delivery failures are NEVER
re-delivered through the same broken transport (no recursive alerting).

### INCIDENT_STATE_LOST  (state seed/persistence degraded)
**Impact:** the run could not recover `incident-state.json` (artifact pruned / download
failed / corrupt / future schema). Cross-run cooldown/flapping memory is reduced.
**Verify:** Ops Console → Incident Delivery → State seed / State trust; delivery log
line `incident-state trust=...`.
**Safe remediation:** none required immediately — the GitHub-side lookup fallback
(`findOpenIssueNumber`) prevents duplicate issues even with no local state. Continuity
returns automatically on the next successful run's artifact.
**Do NOT:** switch state into git (`contents:write`); disable the lookup fallback.

### INCIDENT_DELIVERY_UNAVAILABLE / INCIDENT_DELIVERY_FAILED
**Impact:** one or more Issue writes failed (transport/auth/rate-limit). Evidence
artifacts are STILL produced. `deliveryHealth = DEGRADED|UNAVAILABLE`.
**Verify:** Ops Console → Incident Delivery (failures, transport errors); Actions summary.
**Safe remediation:** check `gh` auth / GitHub status / `issues:write` permission; the
next run retries idempotently (dedup fallback prevents duplicates).
**Do NOT:** open a GitHub issue describing the GitHub-issue failure (recursion). Surface
it in the summary/console/digest only.

### GITHUB_ISSUE_LOOKUP_FAILED
**Impact:** the pre-CREATE dedup lookup failed; a genuinely-new incident might create a
second issue if local state was also lost. Rare (needs both guards to fail same run).
**Verify:** delivery log `issue lookup failed for <code>`.
**Safe remediation:** if a duplicate `[OPS][CRITICAL] <CODE>` pair appears, manually
close the newer; state reconciles next run. **Do NOT:** script bulk issue edits.

### DIGEST_GENERATION_FAILED
**Impact:** `daily-digest.md/.json` not produced this run. No user impact.
**Verify:** `digest` step outcome; missing `ops-status/daily-digest.json`.
**Safe remediation:** re-run ops-health; digest is best-effort + `continue-on-error`.

### DIGEST_DELIVERY_FAILED
**Impact:** none in the current milestone — external digest delivery is DISABLED
(`OPS_DIGEST_DELIVERY_ENABLED=false`). A failure here can only occur once a real
transport is later enabled by the owner.
**Do NOT:** enable a digest transport without owner sign-off on the destination.

### LEGACY_ALERT_PATH_DETECTED  (architecture regression)
**Impact:** a second production GitHub-Issue writer exists (violates single-writer).
**Verify:** `node --test ops/monitor/architecture-guard.test.mjs` fails, naming the file.
**Safe remediation:** remove the Issue mutation from that file; route the signal through
the V5 incident engine (as SERVICE_COMPONENT_DOWN did). **Do NOT:** add a parallel alerter.

---

## V7 Slack daily-digest delivery runbook

Slack carries the ONCE-PER-DAY operational digest only. CRITICAL incidents stay on
GitHub Issues (`incident-delivery.mjs`). **A Slack digest failure is NEVER an
application-runtime failure** — it does not change IAP/OpenAI/Railway/Postgres health
or the release gate. Digest delivery health is surfaced separately
(HEALTHY/DEGRADED/UNAVAILABLE/IDLE/NOT_CONFIGURED) in the Ops Console + Actions summary.

### SLACK_DIGEST_NOT_CONFIGURED
**Impact:** none to product. No digest reaches Slack; the digest artifacts
(daily-digest.md/.json/preview) are still generated. Delivery health = NOT_CONFIGURED.
**Verify:** digest step log `Slack webhook configured: NO`; Ops Console → Daily Digest.
**Safe remediation (owner, one-time):** create a repo **Actions secret**
`OPS_SLACK_WEBHOOK_URL` = a Slack Incoming Webhook URL. No code change needed — the next
scheduled run auto-delivers one digest.
**Do NOT expose:** the webhook URL in source/YAML/logs/issues/chat. It lives only in the
GitHub secret and is injected only into the digest step.

### SLACK_DIGEST_DELIVERY_FAILED
**Impact:** the daily digest could not be posted (network/5xx/timeout after one retry).
No product impact. Delivery health = DEGRADED/UNAVAILABLE; code `DIGEST_DELIVERY_FAILED`.
**Verify:** `digest-delivery.json` event `digest.delivery.failed` + statusCode; console.
**Safe remediation:** check Slack status / the webhook validity. It is best-effort — the
next eligible window retries. Dedup state is only advanced on SUCCESS, so a failed day is
retried, not skipped. **Do NOT:** loop-retry manually; do not open a GitHub Issue for it.

### SLACK_DIGEST_RATE_LIMITED
**Impact:** Slack returned 429. The adapter honors a small Retry-After and retries once;
if still limited it reports failed (no product impact).
**Verify:** `digest-delivery.json` statusCode 429.
**Safe remediation:** none usually needed (once/day cadence rarely rate-limits). **Do
NOT:** remove the retry cap or hammer the webhook.

### SLACK_DIGEST_PAYLOAD_REJECTED
**Impact:** the pre-send safety validator found a prohibited pattern (email/JWT/bearer/
key/blob) in the rendered digest text, so NOTHING was sent. Code
`DIGEST_DELIVERY_PAYLOAD_REJECTED`. This is a safety SUCCESS, not an outage.
**Verify:** `digest-delivery.json` event `digest.delivery.payload_rejected`.
**Safe remediation:** find which digest field introduced the pattern (it should only ever
be operational metadata) and fix the renderer/source; add a test. **Do NOT:** disable the
validator or send the unsafe payload.
