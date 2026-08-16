# Firestore Rules tests — IAP entitlement invariants

Proves the server-authoritative entitlement lock: a client can never raise its
own `paidLinkCredits`/`isPremium`, and a premium link can only be created by
atomically consuming exactly one credit.

## Run (requires Java + Firestore emulator)
```bash
cd test/rules && npm install
cd ../.. && firebase emulators:exec --only firestore "node --test test/rules"
```

> ⚠️ These are emulator tests — they need Java (the Firestore emulator). They are
> **not** part of the pure `node --test` suites and must be run in CI / locally
> with the emulator before deploying `firestore.rules`.
