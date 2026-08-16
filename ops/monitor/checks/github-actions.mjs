// Release-plane evidence: last GitHub Actions workflow-run conclusion via `gh` CLI.
// READ-ONLY. Not runtime traffic. Needs gh auth (or GH_TOKEN) — else UNKNOWN.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const pexec = promisify(execFile);

export async function check(cfg) {
  const wf = cfg.workflow || 'server-concurrency-test.yml';
  const t0 = Date.now();
  try {
    const { stdout } = await pexec('gh', ['run', 'list', '--workflow=' + wf, '--limit', '1', '--json', 'conclusion,status,headSha,createdAt'], { timeout: cfg.timeoutMs || 10000 });
    const rows = JSON.parse(stdout);
    const latencyMs = Date.now() - t0;
    if (!rows.length) return { status: 'UNKNOWN', latencyMs, errorCode: 'NO_RUNS', details: {} };
    const r = rows[0];
    const ok = r.conclusion === 'success';
    return { status: ok ? 'HEALTHY' : r.conclusion ? 'DOWN' : 'UNKNOWN', latencyMs, errorCode: ok ? null : (r.conclusion || 'IN_PROGRESS'), details: { headSha: r.headSha, createdAt: r.createdAt } };
  } catch (e) {
    return { status: 'UNKNOWN', latencyMs: Date.now() - t0, errorCode: 'GH_UNAVAILABLE', details: { note: 'gh CLI not authenticated / unavailable' } };
  }
}
