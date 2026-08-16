// Scoped evidence freshness. A CI invariant is FRESH if the tracked files IN ITS
// SCOPE are unchanged — regardless of the whole-repo HEAD sha. scopeHash is a
// deterministic sha256 of `git ls-tree -r <ref> -- <paths>` (mode+blobSha+path for
// every tracked file in scope). Any content/add/delete in scope changes it.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

// Compute the scope fingerprint at a given ref (commit sha or HEAD).
export function scopeTreeHash(repo, ref, paths) {
  if (!paths || !paths.length) return null;
  let out;
  try {
    out = execFileSync('git', ['ls-tree', '-r', ref, '--', ...paths], { cwd: repo, encoding: 'utf8' });
  } catch { return null; }
  // ls-tree already sorts by path; normalise line endings and hash.
  const norm = out.replace(/\r/g, '').split('\n').filter(Boolean).sort().join('\n');
  return 'sha256:' + createHash('sha256').update(norm).digest('hex').slice(0, 24);
}

// Fresh if evidence.scopeHash matches the current scope hash. No scopeHash (legacy)
// => not fresh (re-verify). currentHash null (scope not computable) => not fresh.
export function evidenceFresh(evidence, currentHash) {
  if (!evidence) return { fresh: false, reason: 'MISSING' };
  if (!evidence.scopeHash) return { fresh: false, reason: 'legacy evidence (no scopeHash) — re-verify' };
  if (currentHash == null) return { fresh: false, reason: 'scope not computable' };
  if (evidence.scopeHash === currentHash) return { fresh: true, reason: 'scope unchanged' };
  return { fresh: false, reason: `STALE — scope changed since ${String(evidence.commitSha || '?').slice(0, 7)}` };
}
