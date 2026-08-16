# Firestore Rules — Safe Rollback (appConfig public read)

**Scope:** how to revert ONLY the `appConfig/version` public-read that was deployed
2026-08-16 to `feedbacktome-79655`, **without** touching any other security invariant.

## Important precision
- We do **NOT** have the exact ruleset that was live in production *before* the
  2026-08-16 deploy. Before that deploy the live read returned 403, i.e. the
  deployed rules denied the appConfig read — they differed from every repo revision.
- Therefore this document is a **forward minimal patch on the CURRENT repo rules**,
  not a "restore exact previous production ruleset".
- Do **NOT** roll back by checking out `439465b:firestore.rules` (or any pre-narrowing
  revision): that reintroduces the **broad** `match /appConfig/{doc}` public read,
  which is *wider* exposure than today — the opposite of a safe rollback.

## Safe rollback = deny the appConfig public read, keep everything else
Current rule (live):
```
match /appConfig/version {
  allow read: if true;
  allow write: if false;
}
```
Rollback patch — flip the read to DENY (or delete the match block entirely; a missing
match defaults to deny):
```
match /appConfig/version {
  allow read: if false;
  allow write: if false;
}
```
Effect: `appConfig/version` live read returns 403 again (RULES_DENY). VersionGate is
FAIL-OPEN, so this does **not** lock any client — it only disables the min-version gate.
`appconfig-rule-drift` would re-fire (by design).

## Invariants that MUST remain unchanged by any rollback
- Transitional `createdAtWithinCompatWindow` (±2 min) — do NOT switch to strict
  `createdAt == request.time`.
- Demo atomic single-use consume (`get()`/`getAfter()`).
- Premium credit enforcement (credit ≥ 1 + atomic −1; no isPremium bypass).
- Client `paidLinkCredits` increase DENY (`noPrivilegeEscalation`).
- Owner immutable fields + no reactivation.
- `processedPurchases` fully client-locked.
- Narrow appConfig scope: only `appConfig/version` may ever be public; other
  `appConfig/*` docs stay default-deny.

## Deploy the rollback (only if needed) — DO NOT run as part of an audit
```
# edit firestore.rules per the patch above, then:
firebase deploy --only firestore:rules \
  --account <authorized-firebase-deploy-account> --project feedbacktome-79655
```
Re-verify: `GET .../documents/appConfig/version` → expect 403 after the rollback.

## Verify the candidate before any (re)deploy
```
firebase emulators:exec --only firestore --project=demo-test \
  "node --test test/rules/firestore.rules.test.mjs"   # expect all PASS
```
