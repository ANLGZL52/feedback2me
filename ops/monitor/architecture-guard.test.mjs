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
