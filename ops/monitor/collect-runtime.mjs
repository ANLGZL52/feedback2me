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
import { collect as collectGcp } from './checks/gcp-functions-logs.mjs';
import { dedupKey, aggregateStatus, mergeEvents } from './runtime-merge.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = join(REPO, 'ops-status', 'runtime-events');
const MAX_LINES = 500; // hard cap per day file — no unbounded growth

const nowIso = new Date().toISOString();
const day = nowIso.slice(0, 10);
const file = join(DIR, day + '.jsonl');

function output(name, value) {
  if (process.env.GITHUB_OUTPUT) { try { appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`); } catch {} }
}

const r = await collect({ limit: 200 }).catch((e) => ({ status: 'DOWN', errorCode: 'COLLECTOR_ERROR', events: [], _e: String(e && e.message) }));
// Railway HTTP logs = the AUTHORITATIVE request-level source (works even when the
// app's structured stdout events don't reach environmentLogs).
const rh = await collectHttp({ limit: 200 }).catch((e) => ({ status: 'DOWN', errorCode: 'COLLECTOR_ERROR', events: [] }));
// GCP Cloud Functions logs (aiSummary). Needs GCP_ACCESS_TOKEN from the workflow's
// short-lived WIF credential; absent -> UNKNOWN/NOT_CONFIGURED (never an outage).
const rg = await collectGcp({}).catch((e) => ({ status: 'DOWN', errorCode: 'COLLECTOR_ERROR', events: [] }));

const allEvents = [...(r.events || []), ...(rh.events || []), ...(rg.events || [])];
console.log(`[runtime-logs] env: status=${r.status} events=${(r.events || []).length} | http: status=${rh.status} events=${(rh.events || []).length} | gcp: status=${rg.status} events=${(rg.events || []).length}`);
const overall = aggregateStatus([r.status, rh.status, rg.status]);
output('status', overall);
output('errorCode', r.errorCode || rh.errorCode || rg.errorCode || '');

if (overall === 'UNKNOWN') {
  // Every source NOT_CONFIGURED — nothing to store; not an error.
  output('events', 0);
  process.exit(0);
}

// Persist new events only (dedup vs today's file), bounded to MAX_LINES.
if (!existsSync(DIR)) mkdirSync(DIR, { recursive: true });
let existing = [];
if (existsSync(file)) { try { existing = readFileSync(file, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean); } catch {} }
const { fresh, merged } = mergeEvents(existing, allEvents, MAX_LINES);
writeFileSync(file, merged.map((e) => JSON.stringify(e)).join('\n') + (merged.length ? '\n' : ''));

console.log(`[runtime-logs] fresh=${fresh.length} stored(total,capped ${MAX_LINES})=${merged.length} -> ${file}`);
output('events', fresh.length);
process.exit(0); // never fail the observability workflow
