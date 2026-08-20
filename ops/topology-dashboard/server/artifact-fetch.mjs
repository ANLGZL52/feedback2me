// Read-only topology dashboard — ARTIFACT FETCH. Downloads the latest SUCCESSFUL Ops
// Health run's ops-status artifact into <repo>/ops-status using the user's authenticated
// gh CLI. No token is read or stored by this script — it relies entirely on `gh auth`.
// Run: npm run ops:fetch
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { REPO_ROOT, OPS_STATUS_DIR } from './artifact-reader.mjs';

function gh(args, opts = {}) {
  const r = spawnSync('gh', args, { cwd: REPO_ROOT, encoding: 'utf8', ...opts });
  return { code: r.status, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

function main() {
  const who = gh(['auth', 'status']);
  if (who.code !== 0) { console.error('[ops:fetch] gh CLI not authenticated. Run `gh auth login` first.'); process.exit(1); }

  const list = gh(['run', 'list', '--workflow', 'Ops Health (read-only)', '--branch', 'main', '--status', 'success', '--limit', '1', '--json', 'databaseId', '-q', '.[0].databaseId']);
  const runId = (list.out || '').trim();
  if (!runId) { console.error('[ops:fetch] no successful Ops Health run found (or gh error): ' + (list.err || '')); process.exit(1); }

  // gh refuses to overwrite existing files; ops-status is gitignored CI output, safe to clear.
  try { rmSync(OPS_STATUS_DIR, { recursive: true, force: true }); } catch { /* ignore */ }
  mkdirSync(OPS_STATUS_DIR, { recursive: true });
  console.log(`[ops:fetch] downloading ops-status artifact from run ${runId} ...`);
  const dl = gh(['run', 'download', runId, '-n', 'ops-status', '-D', OPS_STATUS_DIR]);
  if (dl.code !== 0) { console.error('[ops:fetch] download failed: ' + (dl.err || dl.out)); process.exit(1); }
  console.log(`[ops:fetch] done. ops-status refreshed from run ${runId}. Restart / refresh the dashboard.`);
}

main();
