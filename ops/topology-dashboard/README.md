# Feedback2Me — Interactive Ops Topology / Observability Map

A **local, read-only** interactive system-topology and observability console for Feedback2Me.
Zero runtime dependencies (no `npm install`, no build step) — a pure-Node HTTP server plus a
vanilla SVG frontend. It never deploys, never mutates production, and never exposes secrets.

## Run

```bash
cd ops/topology-dashboard
npm run ops:fetch      # (optional) download the latest ops-status artifact via your gh CLI
npm run ops:topology   # start the read-only server
# open http://127.0.0.1:4173
```

- `ops:fetch` uses your authenticated `gh` CLI to download the latest **successful** Ops Health
  run's `ops-status` artifact into `<repo>/ops-status`. No token is read or stored by this repo.
  If you skip it, the map still renders with `UNKNOWN`/`N/A` status and a banner.
- The server binds to **127.0.0.1:4173 only**. Status polls every 30s (positions never move).

## What it shows

- **SYSTEM MAP** — the real architecture as an interactive graph: pan (drag background),
  zoom (scroll), drag nodes, minimap, search, node/edge selection.
- **Node click** → drawer: role, description, status, depends-on / used-by / observed-by,
  downstream failure impact, alert codes, runbook sections, source files, recent events.
- **Edge click** → relation detail: type, purpose, input/output, security boundary,
  failure behavior, observability coverage.
- **SHOW DEPENDENCIES** / **SHOW FAILURE IMPACT** / **TRACE PATH** — topology analysis
  (highlight upstream+downstream, downstream blast-radius, or the exact path between two nodes).
- **RUNTIME / INCIDENTS / IAP / LOGS / RELEASE** tabs — focused views. IAP shows the 7 money-safety
  invariants and keeps Real IAP TestFlight E2E visibly **DEFERRED**. LOGS is a sanitized event viewer.
- **Global status bar** — env, branch, commit, run, artifact time, runtime, gate, active criticals,
  collector freshness.

## Architecture (files)

```
ops/topology-dashboard/
  server/  server.mjs · topology-model.mjs · artifact-reader.mjs · sanitizer.mjs · artifact-fetch.mjs
  public/  index.html · app.js · styles.css        (vanilla SVG UI — no framework/build)
  topology/ nodes.js · edges.js                    (single source of truth, shared by server + tests)
  topology.test.mjs                                (node/edge integrity, traversal, sanitization)
```

The topology in `topology/*.js` is derived from the real repository (functions/src, ops/monitor,
the Ops Health workflow) — no invented connections. Live status is read from the existing
`ops-status/*` artifacts and normalized (green/amber/red/grey); anything absent shows `UNKNOWN`/`N/A`.

## Note on React Flow

The spec preferred React + React Flow. This implementation uses a **zero-dependency vanilla SVG**
graph instead, deliberately: it must run on any machine with only Node — no `npm install`, no
registry access, no build. It provides the same interactive behaviors (pan/zoom/drag/minimap/
select/dependency-highlight/failure-impact/path-trace/search/animated edges). All data flows
through the same read-only API and sanitizer either way.

## Security

Every API response passes through `sanitizer.mjs` (redacts webhook/JWT/bearer/private-key/email/
API-key/blob; whitelists event fields). This is defense-in-depth on top of the ops pipeline's own
PII-safe events. The dashboard is read-only and localhost-only.
