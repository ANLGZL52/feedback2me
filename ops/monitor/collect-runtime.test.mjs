// Hermetic integration test for collect-runtime.mjs with NO credentials.
// Proves the wired multi-source collector degrades safely: every source
// NOT_CONFIGURED -> status=UNKNOWN, events=0, exit 0, nothing persisted, and no
// token/credential appears in the workflow outputs. No network (each collector
// checks its token first and returns before any fetch).
// Run: node --test ops/monitor/collect-runtime.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(HERE, 'collect-runtime.mjs');

test('no credentials -> UNKNOWN / 0 events / exit 0 / no secret in outputs', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'ops-collect-'));
  const outFile = join(tmp, 'gh_output');
  writeFileSync(outFile, '');
  try {
    // Clean env: strip every collector credential so all sources are NOT_CONFIGURED.
    const env = { ...process.env };
    for (const k of ['OPS_RAILWAY_TOKEN', 'GCP_ACCESS_TOKEN', 'OPS_POSTGRES_DATABASE_URL']) delete env[k];
    env.GITHUB_OUTPUT = outFile;
    const res = spawnSync(process.execPath, [SCRIPT], { env, encoding: 'utf8', timeout: 30000 });
    assert.equal(res.status, 0, `expected exit 0, got ${res.status}; stderr=${res.stderr}`);
    const out = readFileSync(outFile, 'utf8');
    assert.match(out, /status=UNKNOWN/);
    assert.match(out, /events=0/);
    // Never leak a token/credential into the step outputs.
    assert.ok(!/GCP_ACCESS_TOKEN|Bearer |ya29\.|eyJ[A-Za-z0-9_-]{20,}\./.test(out), 'credential-like value in outputs');
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
