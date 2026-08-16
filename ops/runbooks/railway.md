# Runbook — Railway API (`node-railway-api`)

**What it does:** Fastify + Prisma REST backend (opt-in, `USE_RAILWAY_API`). Routes: health, auth (dev bridge), users, links, feedbacks, snapshots, ai. Admin-level Postgres access; security in app code (zod/JWT/ownership), NOT Firestore rules.

**What depends on it:** REST-fallback public feedback (`j-public-feedback-rest`), history (REST mode), AI proxy, `node-postgres`, `node-railway-jwt`.

**Health check:** `chk-railway-health` — HTTP GET `/health` (2xx). Read-only. DOWN here does NOT fail Firestore-mode journeys.

**Common failures:** Railway dyno down, `DATABASE_URL`/`JWT_SECRET` missing (server exits in prod), Postgres unreachable, deploy failure.

**Manual verification:** `curl https://feedback2me-production.up.railway.app/health` → 2xx. Server build: `npm --prefix server run build`.

**Rollback:** Railway dashboard → Deployments → Redeploy previous.

**Logs:** events `chk-railway-health`; Railway logs (no PII in ops events).
