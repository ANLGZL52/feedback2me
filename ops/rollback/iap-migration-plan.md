# IAP entitlement hardening — safe coordinated cutover

Moves paid-credit grants behind server-verified `iapVerify` and locks
`firestore.rules` so a client can no longer forge `paidLinkCredits`/`isPremium`.
Three surfaces must land in a safe order. **Do not deploy the locked rules before
the trusted verification path is live and old clients are drained** — otherwise a
still-shipped old client (which grants credit locally) can no longer write its
credit and paying users get nothing.

## Surfaces
1. **`iapVerify` Cloud Function** (`functions/` — needs Blaze, already active) with secrets
   `APPLE_SHARED_SECRET`, `PLAY_SERVICE_ACCOUNT_JSON` and param `ANDROID_PACKAGE_NAME`.
2. **Locked `firestore.rules`** (users entitlement lock + `processedPurchases` deny + `linkCreateConsumesEntitlement`).
3. **New Flutter client** (calls `iapVerify`, no local `paidLinkCredits` write).

## Order — app with NO production users yet (internal-validation phase)
This app is in internal validation; if there is no meaningful installed base, the
three land together with no old-client risk:
1. Configure secrets: `firebase functions:secrets:set APPLE_SHARED_SECRET` / `PLAY_SERVICE_ACCOUNT_JSON`; set `ANDROID_PACKAGE_NAME`.
2. **Verify the rules in the emulator** (`test/rules`, needs Java) — the rules↔client atomic-consume contract MUST pass before deploy.
3. Deploy `iapVerify`: `firebase deploy --only functions:iapVerify` (aiSummary untouched).
4. Deploy rules: `firebase deploy --only firestore:rules`.
5. Build & internally distribute the new client (TestFlight / Play internal).

## Order — app WITH an existing installed base
Old clients grant credit locally; locking rules breaks their purchases. The app
currently has **no version gate** (see audit), so add one first or accept a hard
cutover:
1. Deploy `iapVerify` (server; no effect on old clients — additive).
2. Release the new client (calls `iapVerify`); it coexists with old clients (rules not yet locked, both grant paths work).
3. Add a **min-version gate** and force-update / drain old clients until the old-client population is negligible.
4. **Then** deploy the locked `firestore.rules` (only `iapVerify` can grant thereafter).

## Old-client compatibility
- Before rules lock: old client's local `paidLinkCredits` write still works (rules permissive) → no breakage during the drain window.
- After rules lock: an old client's local credit write is DENIED; its purchase stays queued/uncredited until the user updates. This is why rules lock is last (and gated on drain for an app with users).
- New client is idempotent + retry-safe: a transient `iapVerify` failure keeps the purchase queued; the store-authoritative idempotency key makes replays grant +0.

## Rollback
- Revert `firestore.rules` to the previous (unlocked) version and redeploy → clients can write again (temporarily restores the old, insecure-but-working behavior). `iapVerify` can stay deployed (harmless).
- The new client tolerates `iapVerify` being unavailable (transient → purchase queued), so a function rollback does not lose purchases.

## Not in this PR
No deploy, no secret set, no client release. `aiSummary` untouched. The Railway
backend mirror (`server/src/routes/links.ts`) still reads `isPremium` — a residual
follow-up if the Railway data path is ever enabled (default off).
