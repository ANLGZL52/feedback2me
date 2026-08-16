// CI invariant: architecture model self-consistency (component-inventory <-> dependency-graph).
// READ-ONLY (reads docs/architecture/*.json). Fails if endpoints invalid, edges lack
// evidence, or nodes are orphaned. A first guard against architecture drift.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export async function check() {
  const dir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'docs', 'architecture');
  try {
    const inv = JSON.parse(readFileSync(join(dir, 'component-inventory.json'), 'utf8'));
    const g = JSON.parse(readFileSync(join(dir, 'dependency-graph.json'), 'utf8'));
    const ids = new Set(inv.components.map((c) => c.id));
    const problems = [];
    for (const e of g.edges) {
      if (!ids.has(e.from)) problems.push(`edge ${e.id} bad from ${e.from}`);
      if (!ids.has(e.to)) problems.push(`edge ${e.id} bad to ${e.to}`);
      if (!e.evidence || !e.evidence.length) problems.push(`edge ${e.id} no evidence`);
    }
    const touched = new Set();
    g.edges.forEach((e) => { touched.add(e.from); touched.add(e.to); });
    const orphans = inv.components.filter((c) => !touched.has(c.id)).map((c) => c.id);
    problems.push(...orphans.map((o) => `orphan ${o}`));
    const ok = problems.length === 0;
    return { status: ok ? 'HEALTHY' : 'DOWN', errorCode: ok ? null : 'ARCH_DRIFT', details: { components: inv.components.length, edges: g.edges.length, problems: problems.slice(0, 10) } };
  } catch (e) {
    return { status: 'UNKNOWN', errorCode: 'READ_FAIL', details: { error: String(e.message) } };
  }
}
