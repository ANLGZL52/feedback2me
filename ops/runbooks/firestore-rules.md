# Runbook — Firestore Security Rules (`node-firestore-rules`)

**What it does:** The client↔Firestore security boundary. Server-authoritative link lifecycle (createdAt+duration), atomic demo (`getAfter`), credit/demo entitlement on create, owner immutability, `appConfig` public-read.

**What depends on it:** every client Firestore read/write; owner create + public feedback journeys.

**Health check:** `chk-firestore-rules-public` — Firestore REST public read of `appConfig/version`. `200/404` = read allowed (HEALTHY); **`403` = rule not deployed / drift (DEGRADED)**; network/5xx = DOWN. Deep behavior (entitlement, atomic demo, createdAt window) = CI invariant `ci-rules-emulator` (needs Java), NOT live.

**Common failures:** repo rules edited but **not deployed** (403 on appConfig — the current live state), a deploy that loosened/broke a rule, drift vs `firestore.rules`.

**Manual verification:** run the emulator suite: `firebase emulators:exec --only firestore "node --test test/rules/firestore.rules.test.mjs"` (expects 30/30). For live: the appConfig REST read should be 200 once the appConfig rule is deployed.

**Rollback:** `git show <prev>:firestore.rules > firestore.rules && firebase deploy --only firestore:rules`.

**Logs:** events `chk-firestore-rules-public`; Firebase Console → Firestore → Rules.
