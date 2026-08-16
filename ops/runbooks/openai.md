# Runbook — OpenAI + /ai/chat proxy (`node-openai`, `node-ai-proxy`)

**What it does:** Server-side AI. `OpenAiAudienceClient` (no key) → Railway `POST /ai/chat` (holds `OPENAI_API_KEY`) → `api.openai.com/v1/chat/completions`, model `gpt-4o-mini`. Summarizes/groups REAL feedback; never generates feedback.

**What depends on it:** AI summary journey (`j-ai-summary`) — **soft** dep. Down → DEGRADED (heuristic fallback keeps the journey working).

**Health check:** `chk-ai-proxy` / `chk-openai` — **no safe live check** (POST would spend tokens). Host reachability inferred from `chk-railway-health`. Reports **UNKNOWN** live. Deep check = synthetic-staging (a tiny prompt on a staging server).

**Common failures:** `OPENAI_API_KEY` unset (proxy → 503 `ai_not_configured`), OpenAI outage, rate limit (proxy caps 40/min per IP), quota/billing.

**Manual verification:** on staging, `POST /ai/chat` with a minimal `messages` payload → 200 + `choices[0].message.content`. App-side: AI unset/failed → heuristic summary still renders.

**Rollback:** none needed (fail-open to heuristics). Fix key/quota in server env / OpenAI dashboard.

**Logs:** events `chk-ai-proxy` (metadata only — never prompts/feedback text).
