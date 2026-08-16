#!/usr/bin/env node
// Scheduled Railway runtime-log collection step. Read-only. Runs the collector,
// persists BOUNDED, deduplicated, PII-safe runtime events to
// ops-status/runtime-events/<date>.jsonl, and reports status to the workflow.
// NEVER fails the workflow: a missing OPS_RAILWAY_TOKEN -> NOT_CONFIGURED, and a
// collector/auth error is reported but exits 0 (collector failure != backend outage).
import { readFileSync, writeFileSync, existsSync, mkdirSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { collect } from './checks/railway-runtime-logs.mjs';
import { collect as collectHttp } from './checks/railway-http-logs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = join(REPO, 'ops-status', 'runtime-events');
const MAX_LINES = 500; // hard cap per day file — no unbounded growth

const nowIso = new Date().toISOString();
const day = nowIso.slice(0, 10);
const file = join(DIR, day + '.jsonl');

// safe fingerprint (Phase 15) — only non-content fields.
const fp = (e) => [e.componentId, e.eventType, e.errorCode, e.routeId, e.statusClass].join('|');
// dedup key so the same request/line is stored once. Prefer a per-request id
// (Fastify correlationId or Railway requestId) so distinct requests aren't collapsed.
const key = (e) => [e.deploymentId, e.timestamp, e.eventType, e.correlationId || e.railwayRequestId || fp(e)].join('#');

function output(name, value) {
  if (process.env.GITHUB_OUTPUT) { try { appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`); } catch {} }
}

const r = await collect({ limit: 200 }).catch((e) => ({ status: 'DOWN', errorCode: 'COLLECTOR_ERROR', events: [], _e: String(e && e.message) }));
// Railway HTTP logs = the AUTHORITATIVE request-level source (works even when the
// app's structured stdout events don't reach environmentLogs).
const rh = await collectHttp({ limit: 200 }).catch((e) => ({ status: 'DOWN', errorCode: 'COLLECTOR_ERROR', events: [] }));

const allEvents = [...(r.events || []), ...(rh.events || [])];
console.log(`[runtime-logs] env: status=${r.status} scanned=${r.logLinesScanned ?? 0} events=${(r.events || []).length} | http: status=${rh.status} rows=${rh.rowsScanned ?? 0} events=${(rh.events || []).length}`);
output('status', r.status === 'UNKNOWN' && rh.status === 'UNKNOWN' ? 'UNKNOWN' : (r.status === 'HEALTHY' || rh.status === 'HEALTHY' ? 'HEALTHY' : 'DOWN'));
output('errorCode', r.errorCode || rh.errorCode || '');

if (r.status === 'UNKNOWN' && rh.status === 'UNKNOWN') {
  // NOT_CONFIGURED — nothing to store; not an error.
  output('events', 0);
  process.exit(0);
}
// override r.events with the merged set for storage below.
r.events = allEvents;

// Persist new events only (dedup vs today's file), bounded to MAX_LINES.
if (!existsSync(DIR)) mkdirSync(DIR, { recursive: true });
let existing = [];
if (existsSync(file)) { try { existing = readFileSync(file, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean); } catch {} }
const seen = new Set(existing.map(key));
const fresh = (r.events || []).filter((e) => !seen.has(key(e)));
const merged = [...existing, ...fresh].slice(-MAX_LINES); // cap
writeFileSync(file, merged.map((e) => JSON.stringify(e)).join('\n') + (merged.length ? '\n' : ''));

console.log(`[runtime-logs] fresh=${fresh.length} stored(total,capped ${MAX_LINES})=${merged.length} -> ${file}`);
output('events', fresh.length);
process.exit(0); // never fail the observability workflow
