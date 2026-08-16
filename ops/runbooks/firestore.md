# Runbook — Cloud Firestore (`node-firestore`)

**What it does:** Default persistence domain. Collections `users`, `links`, `feedbacks`, `appConfig/version`, `processedPurchases`, `users/{uid}/audienceScoreSnapshots`.

**What depends on it:** owner create, public feedback, AI summary, history journeys; `node-firestore-rules`, `node-cloud-functions`.

**Health check:** `chk-firestore-appconfig` (reachabilityOnly) — Firestore REST read of `appConfig/version` with the public web apiKey. Any HTTP response = reachable. Read-only, no user data.

**Common failures:** Firestore regional outage (5xx/timeout), quota exhaustion, index missing (query fails).

**Manual verification:** `curl "https://firestore.googleapis.com/v1/projects/feedbacktome-79655/databases/(default)/documents/appConfig/version?key=<PUBLIC_WEB_KEY>"` → HTTP response (200/404/403) proves reachability.

**Rollback:** N/A (managed). For index issues: re-deploy `firestore.indexes.json`.

**Logs:** events `chk-firestore-appconfig`; Firebase Console → Firestore usage / rules metrics.
