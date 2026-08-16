# Runbook — PostgreSQL (`node-postgres`)

**What it does:** Prisma-backed relational store for the Railway API (opt-in domain). Models User, OAuthAccount, Link, Feedback, AudienceScoreSnapshot, AudienceReportBody.

**What depends on it:** `node-railway-api` → REST-fallback public feedback + history journeys. **Not used in Firestore-default builds.**

**Health check:** `chk-postgres` — **no direct safe check** (no admin creds in ops). Inferred from `chk-railway-health` (if the API is up, its DB is usually reachable). Reports **UNKNOWN** live.

**Common failures:** Railway Postgres plan down, connection-pool exhaustion, migration drift (`prisma db push` not applied).

**Manual verification:** on a staging DB: `DATABASE_URL=... npm --prefix server run db:push` then the concurrency test `node --test server/test/demo-concurrency.test.mjs` (needs a disposable Postgres — see GitHub Actions `server-concurrency-test.yml`).

**Rollback:** Railway → Postgres → restore snapshot (managed). Never run destructive migrations on prod.

**Logs:** Railway Postgres metrics; ops infers via `chk-railway-health`.
