# Runbook — Version Gate (`node-version-gate-svc`, `appConfig/version`)

**What it does:** Owner-app min-version gate. Reads `appConfig/version.minSupportedBuild`; if `kAppBuild`
is lower → force-update screen. **Fail-open** (read error → app opens). Only gate-aware (Release A+)
clients read it; pre-gate legacy clients never do. Public feedback bypasses it.

**What depends on it:** owner-start (soft), legacy-cutover journeys.

**Health check:** `chk-version-config` — Firestore REST read of `appConfig/version`. `200` → returns
`minSupportedBuild`/`latestBuild` (status bar); `403` → **appConfig public-read rule not deployed
(DEGRADED)** — the current live state; `404` → doc not created yet.

**Common failures:** appConfig rule not deployed (403 — deploy `firestore:rules`); doc not created
(404 — create `appConfig/version` in Console with `minSupportedBuild`/`latestBuild`); a wrong
`minSupportedBuild` that force-updates everyone.

**Manual verification:** after deploying the appConfig rule, the REST read returns 200 with the fields;
set `minSupportedBuild` below current build to confirm no false force-update.

**Rollback:** lower/remove `minSupportedBuild` in `appConfig/version` (Console); redeploy prior rules.

**Logs:** events `chk-version-config`; Firebase Console → Firestore `appConfig/version`.
