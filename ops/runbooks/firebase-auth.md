# Runbook — Firebase Auth (`node-firebase-auth`)

**What it does:** Owner identity via Google + Apple sign-in (no anonymous / email-password). Provides `uid`.

**What depends on it:** owner-start, create-demo, create-premium journeys. **Public feedback does NOT depend on auth.**

**Health check:** `chk-firebase-auth` — **no safe live check** (would require a real sign-in). Reports **UNKNOWN** live. Deep check = synthetic-staging (sign in on a dedicated TEST account) — not run against production.

**Common failures:** OAuth client misconfig (SHA / bundle id / reversed client id), Apple key expiry, provider disabled in Console.

**Manual verification:** sign in on a TEST account in a debug build; confirm `uid` and that `_AuthGate` reaches the owner home.

**Rollback:** revert the auth provider config in Firebase Console → Authentication → Sign-in method.

**Logs:** Firebase Console → Authentication; app debug logs (no tokens/PII in ops events).
