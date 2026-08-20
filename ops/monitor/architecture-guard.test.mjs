// Observability V6 — SINGLE-WRITER architecture guard (Phase 24). Fails if any
// production ops module other than the canonical incident-delivery adapter contains a
// GitHub Issue MUTATION (create/comment/close/reopen). This is what keeps the "exactly
// one production operational Issue writer" invariant from silently regressing.
// Run: node --test ops/monitor/architecture-guard.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { RUNBOOK_SECTIONS } from './incident-actions.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
// The ONLY file permitted to mutate GitHub Issues in production.
const ALLOWED_WRITERS = new Set(['incident-delivery.mjs']);
// Issue-mutation signatures: gh(['issue','create'|'comment'|'close'|'reopen', ...]) or `gh issue create`.
const MUTATION = [
  /(['"])issue\1\s*,\s*(['"])(create|comment|close|reopen)\2/,
  /\bgh\s+issue\s+(create|comment|close|reopen)\b/,
];

const productionModules = () => readdirSync(HERE)
  .filter((f) => f.endsWith('.mjs') && !f.endsWith('.test.mjs'))
  .concat(readdirSync(join(HERE, 'checks')).filter((f) => f.endsWith('.mjs') && !f.endsWith('.test.mjs')).map((f) => join('checks', f)));

describe('single production Issue writer', () => {
  test('no production module except incident-delivery.mjs mutates GitHub Issues', () => {
    const offenders = [];
    for (const rel of productionModules()) {
      const base = rel.split(/[\\/]/).pop();
      if (ALLOWED_WRITERS.has(base)) continue;
      const src = readFileSync(join(HERE, rel), 'utf8');
      if (MUTATION.some((re) => re.test(src))) offenders.push(rel);
    }
    assert.deepEqual(offenders, [], `Unauthorized GitHub Issue writer(s): ${offenders.join(', ')}. Route operational alerts through the V5 incident pipeline instead.`);
  });

  test('the retired legacy alert.mjs contains NO Issue mutation', () => {
    const src = readFileSync(join(HERE, 'alert.mjs'), 'utf8');
    assert.ok(MUTATION.every((re) => !re.test(src)), 'alert.mjs must not write GitHub Issues (retired writer).');
  });

  test('incident-delivery.mjs IS the canonical writer (still present)', () => {
    const src = readFileSync(join(HERE, 'incident-delivery.mjs'), 'utf8');
    assert.ok(MUTATION.some((re) => re.test(src)), 'incident-delivery.mjs should contain the Issue transport.');
  });
});

// V8 Phase 15 guard — every CRITICAL alert code that can reach the incident engine MUST map
// to a runbook section, and that section MUST exist in RUNBOOK.md. Prevents a dangling
// CRITICAL (an Issue created with no remediation link) from silently regressing.
describe('every CRITICAL alert code has runbook remediation', () => {
  // Statically-emitted CRITICAL codes: alert('DOMAIN','CODE','CRITICAL', ...) in evaluate-runtime.mjs.
  const criticalFromEvaluator = () => {
    const src = readFileSync(join(HERE, 'evaluate-runtime.mjs'), 'utf8');
    const re = /alert\(\s*'[A-Z]+'\s*,\s*'([A-Z0-9_]+)'\s*,\s*'CRITICAL'/g;
    return [...src.matchAll(re)].map((m) => m[1]);
  };
  // Money-safety invariant codes are pushed CRITICAL via the push() helper in iap-invariants.mjs.
  const criticalFromInvariants = () => {
    const src = readFileSync(join(HERE, 'iap-invariants.mjs'), 'utf8');
    const re = /push\(\s*'([A-Z0-9_]+)'/g;
    return [...src.matchAll(re)].map((m) => m[1]);
  };
  const allCriticalCodes = () => [...new Set([...criticalFromEvaluator(), ...criticalFromInvariants()])];
  const runbookHeaders = () => new Set(
    readFileSync(join(HERE, '..', 'RUNBOOK.md'), 'utf8')
      .split('\n').filter((l) => l.startsWith('## '))
      .map((l) => l.slice(3).trim().split(/\s+/)[0]) // first token after '## '
  );

  test('discovered at least the known IAP/OpenAI/Postgres CRITICAL codes (scan sanity)', () => {
    const codes = allCriticalCodes();
    for (const c of ['IAP_VERIFY_DOWN', 'IAP_LATENCY_DEGRADED', 'IAP_INVALID_PRODUCT_CREDITED', 'POSTGRES_CRITICAL', 'OPENAI_DEGRADED', 'SERVICE_COMPONENT_DOWN'])
      assert.ok(codes.includes(c), `scan failed to find CRITICAL code ${c}`);
  });

  test('every emitted CRITICAL code maps to a RUNBOOK_SECTIONS entry', () => {
    const unmapped = allCriticalCodes().filter((c) => !RUNBOOK_SECTIONS[c]);
    assert.deepEqual(unmapped, [], `CRITICAL codes with no runbook mapping (dangling): ${unmapped.join(', ')}`);
  });

  test('every mapped runbook section exists as a header in RUNBOOK.md', () => {
    const headers = runbookHeaders();
    const missing = [...new Set(Object.values(RUNBOOK_SECTIONS))].filter((s) => !headers.has(s));
    assert.deepEqual(missing, [], `RUNBOOK_SECTIONS targets with no '## ' header in RUNBOOK.md: ${missing.join(', ')}`);
  });
});
