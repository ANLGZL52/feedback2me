// Read-only topology dashboard — ARTIFACT READER. Reads the existing ops-status/*
// artifacts produced by the Ops Health workflow. Never writes, never mutates production.
// If an artifact is missing (fresh clone / not fetched yet) it returns null and the model
// falls back to UNKNOWN / N/A — the dashboard still renders.
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { sanitizeEvent } from './sanitizer.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
// ops/topology-dashboard/server -> repo root is three levels up.
export const REPO_ROOT = join(HERE, '..', '..', '..');
export const OPS_STATUS_DIR = join(REPO_ROOT, 'ops-status');

function readJson(name) {
  const p = join(OPS_STATUS_DIR, name);
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; }
}

function readEventsDir(rel, cap) {
  const dir = join(OPS_STATUS_DIR, rel);
  if (!existsSync(dir)) return [];
  const out = [];
  let files = [];
  try { files = readdirSync(dir).filter((f) => f.endsWith('.jsonl') || f.endsWith('.json')); } catch { return []; }
  for (const f of files) {
    try {
      const txt = readFileSync(join(dir, f), 'utf8');
      for (const line of txt.split('\n')) {
        const s = line.trim();
        if (!s) continue;
        try { const ev = sanitizeEvent(JSON.parse(s)); if (ev) out.push(ev); } catch { /* skip bad line */ }
      }
    } catch { /* skip unreadable file */ }
  }
  return out.slice(-cap);
}

export function readArtifacts() {
  const health = readJson('runtime-health.json');
  const incidentState = readJson('incident-state.json');
  const incidentActions = readJson('incident-actions.json');
  const digestState = readJson('digest-state.json');
  const digestDelivery = readJson('digest-delivery.json');
  const trend = readJson('trend.json');
  const latest = readJson('latest.json');

  // freshness of the snapshot itself
  let artifactTimestamp = null;
  const hp = join(OPS_STATUS_DIR, 'runtime-health.json');
  if (existsSync(hp)) { try { artifactTimestamp = statSync(hp).mtime.toISOString(); } catch { /* ignore */ } }
  if (health && health.generatedAt) artifactTimestamp = health.generatedAt;

  const events = [...readEventsDir('events', 400), ...readEventsDir('runtime-events', 400)]
    .sort((a, b) => String(b.time).localeCompare(String(a.time)))
    .slice(0, 500);

  return {
    present: !!health,
    health, incidentState, incidentActions, digestState, digestDelivery, trend, latest,
    events, artifactTimestamp,
  };
}
