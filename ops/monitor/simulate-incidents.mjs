#!/usr/bin/env node
// Observability V4 — Phase 25 simulated incident proof. DETERMINISTIC, DRY-RUN ONLY.
// For each representative CRITICAL scenario, shows: alert -> incident action ->
// Issue title/body preview -> runbook mapping -> release gate. Creates NO real Issue
// (never calls a transport). Renders a markdown artifact + prints it.
import { writeFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { computeIncidentActions, renderIssueBody, issueTitle, issueLabels, validateIssuePayload, deliveryMode } from './incident-actions.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SLO = JSON.parse(readFileSync(join(REPO, 'ops', 'observability-slo.json'), 'utf8'));
// Fixed epoch — no Date.now(), fully deterministic.
const NOW = Date.parse('2026-08-19T12:00:00Z');
const startedAt = new Date(NOW - 5 * 60000).toISOString();
const DEP = { commit: 'c982122', build: '22' };

const SCENARIOS = [
  { domain: 'POSTGRES', code: 'POSTGRES_CRITICAL', message: 'Postgres unhealthy for 3 consecutive probes', evidence: { consecutiveFailures: 3 } },
  { domain: 'IAP', code: 'IAP_VERIFY_DOWN', message: 'iapVerify unreachable / erroring for the whole window', evidence: { errorRate: 1 } },
  { domain: 'IAP', code: 'IAP_MONEY_SAFETY_BREACH', message: 'credit granted without a verified Apple success', evidence: { violations: 1 } },
  { domain: 'OPENAI', code: 'OPENAI_DEGRADED', message: 'OpenAI failure rate 60% (6/10)', evidence: { rate: 0.6 } },
  { domain: 'RAILWAY', code: 'RAILWAY_5XX_ELEVATED', message: '5xx rate 40% (8/20)', evidence: { rate: 0.4 } },
  { domain: 'COLLECTOR', code: 'COLLECTOR_STALE', message: 'no fresh collection for 100 min (> 95)', evidence: { ageMinutes: 100 } },
];

export function simulate() {
  const gateStatus = 'BLOCK';
  const ctx = { currentRuntimeHealth: 'UNHEALTHY', productReleaseGate: gateStatus, runUrl: 'https://github.com/ANLGZL52/feedback2me/actions/runs/<run>' };
  const mode = deliveryMode(false, true); // proof runs in the default safe posture
  const L = [`# Feedback2Me — Simulated Incident Proof (DRY-RUN)`, '',
    `Deterministic fixture demonstration. Delivery mode: **${mode}** — **0 real GitHub Issues created**.`,
    `Each scenario shows the incident decision, the exact Issue payload that WOULD be sent, the runbook mapping, and the release-gate effect.`, ''];
  for (const s of SCENARIOS) {
    const alert = { ...s, severity: 'CRITICAL', startedAt, deployContextAtStart: DEP };
    const { incidents, actions } = computeIncidentActions({ alerts: [alert], prevIncidents: [], config: SLO, now: NOW, deployment: DEP, gateStatus });
    const inc = incidents[0], a = actions[0];
    const title = issueTitle(inc), body = renderIssueBody(inc, ctx), safety = validateIssuePayload(title, body);
    L.push(`## ${s.code}  (${s.domain})`);
    L.push(`- **Alert → incident action:** \`${a.action}\` (${a.reason})`);
    L.push(`- **Runbook mapping:** ops/RUNBOOK.md → \`${inc.runbookSection}\``);
    L.push(`- **Release gate:** ${gateStatus} (this code is release-blocking per SLO: ${(SLO.releaseGate.blockOn || []).includes(s.code)})`);
    L.push(`- **Labels:** ${issueLabels(inc).join(', ')}`);
    L.push(`- **Payload safety:** ${safety.safe ? 'SAFE ✅' : 'REJECTED ❌ ' + safety.code}`);
    L.push('', '**Issue title preview:**', '```', title, '```', '**Issue body preview:**', '```', body, '```', '');
  }
  return L.join('\n');
}

function main() {
  const md = simulate();
  const dir = join(REPO, 'ops-status');
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'incident-simulation.md'), md);
  console.log(md);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
