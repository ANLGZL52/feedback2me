#!/usr/bin/env node
// RETIRED WRITER (Observability V6) — this module NO LONGER writes GitHub Issues.
//
// Operational GitHub incidents are delivered EXCLUSIVELY through the canonical V5+
// incident-delivery pipeline (ops/monitor/incident-delivery.mjs). There must be only
// ONE production Issue writer. The live component-DOWN signal this module used to
// surface has been PORTED into the canonical evaluator as SERVICE_COMPONENT_DOWN
// (see ops/monitor/evaluate-runtime.mjs), so no coverage was lost.
//
// What remains here: the PURE decideAlert() decision (still imported by alert.test.mjs)
// and a READ-ONLY main() that prints the legacy decision for local diagnostics. It
// makes NO `gh` calls and performs NO Issue mutation. Do not re-add Issue writes here —
// route any new operational alert through the incident engine instead.
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/**
 * Pure alert decision (exported for tests). Runtime-only, DOWN is the authority.
 *
 * LIVE DOWN is the sole alert trigger:
 *  - a live component whose status === 'DOWN', OR
 *  - an OPEN incident whose underlying component is CURRENTLY DOWN.
 *
 * DEGRADED is dashboard-only and NEVER alerts — even though reconcileIncidents
 * opens an OPEN incident for a DEGRADED component (severity 'P2'), so a blanket
 * "any open incident" trigger would wrongly fire on DEGRADED. We therefore gate
 * incidents on the component's current DOWN status, not on incident presence.
 * Incident severities in this model are status-derived (DOWN->P1, DEGRADED->P2)
 * and are never P0, so there is no "live-sourced P0 incident" concept to honor.
 * Release blockers (snapshot.blockers) are IGNORED here on purpose.
 */
export function decideAlert(snapshot) {
  const s = snapshot || {};
  const comp = s.components || {};
  const statusOf = (id) => (comp[id] && comp[id].status) || 'UNKNOWN';
  const down = Object.entries(comp)
    .filter(([, c]) => c && c.status === 'DOWN')
    .map(([id]) => id);
  const openInc = (s.incidents || []).filter((i) => i && i.status === 'OPEN');
  // Only incidents whose underlying component is CURRENTLY DOWN are alertable.
  const alertableInc = openInc.filter((i) => i.componentId && statusOf(i.componentId) === 'DOWN');
  const alert = down.length > 0 || alertableInc.length > 0;
  return {
    alert,
    down,
    openIncidentCount: openInc.length,
    alertableIncidentCount: alertableInc.length,
    reasons: [
      ...down.map((id) => `component ${id} DOWN`),
      ...alertableInc.map((i) => `incident ${i.componentId} DOWN`),
    ],
  };
}

// ---- READ-ONLY runner (no GitHub writes; skipped when imported for tests) ----
// Prints the legacy decision for local diagnostics only. The component-DOWN signal is
// now delivered through the canonical incident pipeline (SERVICE_COMPONENT_DOWN).
function main() {
  const p = join(REPO, 'ops-status', 'latest.json');
  if (!existsSync(p)) { console.log('[alert] (retired writer) no snapshot'); return; }
  const s = JSON.parse(readFileSync(p, 'utf8'));
  const d = decideAlert(s);
  console.log(`[alert] (retired writer — read-only) decision: alert=${d.alert} down=[${d.down.join(',')}] openIncidents=${d.openIncidentCount}`);
  console.log('[alert] GitHub Issue delivery is handled EXCLUSIVELY by the V5 incident pipeline (SERVICE_COMPONENT_DOWN). This module makes NO gh calls.');
}

// Only run side effects when invoked directly, not when imported by tests.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
