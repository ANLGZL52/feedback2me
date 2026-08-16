# Runbook — Public Feedback (`node-fhtml`, journey `j-public-feedback`)

**What it does:** Anonymous responders open `/f/<code>` → Hosting rewrite → `f.html` → default Firestore
direct (query `links`, batch-write `feedbacks` + demo close) gated by Firestore Rules; opt-in Railway
REST fallback via `<meta name="ftm-public-api">`. localStorage marker is UX-only.

**What depends on it:** the core acquisition funnel. Critical journey.

**Health check:** `chk-fhtml` (page reachable, HTTP GET). Full path health = hosting + f.html + firestore + rules
(with Railway as fallback). **Anonymous — not gated by Firebase Auth or the min-version gate.**

**Common failures:** hosting down / bad rewrite (`/f/<code>` 404), Firestore down (→ DEGRADED if Railway up, else DOWN),
rules drift blocking `feedbacks.create`, expired/consumed link (expected, not an incident).

**Manual verification:** open a real `/f/<code>` for an active link in a browser; page loads, form submits,
success state + marker written. Concurrency: two simultaneous demo submits → exactly one succeeds.

**Rollback:** hosting rollback (Console); rules rollback (git + `firebase deploy --only firestore:rules`).

**Logs:** events `chk-fhtml`, `chk-hosting`, `chk-firestore-*`. Never log feedback text / responder names.
