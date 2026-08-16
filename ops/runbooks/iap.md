# Runbook — IAP + credit grant (`node-iap-service`, `node-cloud-functions`)

**⚠ STATIC P0 SECURITY GAP (open):** `IapService._grantLinkCreditToCurrentUser` grants
`paidLinkCredits + 1` **client-side with no receipt verification** and does NOT call the
`iapVerify` Cloud Function (`lib/services/iap_service.dart:192-213`). Committed `firestore.rules`
`noPrivilegeEscalation` would reject a client credit increase. **Free-premium risk.** This caps the
purchase-credit journey at DEGRADED and is a permanent **release blocker** until fixed (restore
`iapVerify`, commit `5b204d5`). NOT fixed by ops — reported.

**What it does (intended):** purchase → `iapVerify` (onCall) → Apple/Google receipt verify → Admin-SDK
credit grant, idempotent via `processedPurchases`.

**What depends on it:** purchase-credit journey; `paidLinkCredits` → premium create.

**Health check:** `chk-cloud-functions` — **UNKNOWN** live (onCall needs auth + a receipt; not safely invokable). Store checks `chk-apple-store`/`chk-google-play` — UNKNOWN.

**Common failures:** the static gap above; `APPLE_SHARED_SECRET`/`PLAY_SERVICE_ACCOUNT_JSON` missing; receipt-verify endpoint outage; sandbox vs prod receipt mismatch.

**Manual verification:** in a debug build with the intended flow restored, a sandbox purchase should route through `iapVerify` and increment credits exactly once (replay = no double grant).

**Rollback:** revert credit-granting change; redeploy functions + tightened rules together.

**Logs:** Firebase Functions logs for `iapVerify` (no receipts/tokens in ops events).
