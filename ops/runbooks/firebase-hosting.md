# Runbook — Firebase Hosting (`node-firebase-hosting`)

**What it does:** Serves `web_static/` (landing + `f.html` + legal) at `feedbacktome-79655.web.app`; rewrites `/f`,`/f/**` → `f.html`. Entry for the entire public feedback funnel.

**What depends on it:** `node-fhtml`, public feedback journey (`j-public-feedback`).

**Health check:** `chk-hosting` — HTTP GET `https://feedbacktome-79655.web.app/` (2xx). Read-only.

**Common failures:** Hosting outage (5xx), bad deploy (wrong `public` dir / missing rewrites → 404 on `/f/<code>`), DNS.

**Manual verification:** `curl -I https://feedbacktome-79655.web.app/` and `.../f/anycode` → both 200; f.html served.

**Rollback:** Firebase Console → Hosting → Release history → Roll back to previous release. (Do NOT rely on a `firebase hosting:rollback` command in docs.)

**Logs:** `ops-status/events/<date>.jsonl` (checkId `chk-hosting`); Firebase Console → Hosting usage.
