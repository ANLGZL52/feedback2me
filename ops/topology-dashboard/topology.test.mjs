// Topology dashboard tests. Deterministic; no network, no artifacts required (uses fixtures).
// Run: node --test topology.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { NODES, GROUPS, NODE_SIZE } from './topology/nodes.js';
import { EDGES } from './topology/edges.js';
import { CATEGORIES } from './topology/nodes.js';
import {
  normalizeStatus, statusForNode, dependsOn, usedBy, downstreamClosure, upstreamClosure,
  pathTrace, buildTopology, buildNodeDetail, buildMeta, computeGroups,
} from './server/topology-model.mjs';
import { redact, deepRedact, sanitizeEvent } from './server/sanitizer.mjs';

const NODE_IDS = new Set(NODES.map((n) => n.id));

// A representative live artifact fixture (HEALTHY baseline, IAP idle, digest live).
const art = {
  present: true,
  artifactTimestamp: '2026-08-20T14:04:00Z',
  health: {
    generatedAt: '2026-08-20T14:04:00Z', currentRuntimeHealth: 'HEALTHY', observabilityPlatformStatus: 'FULL',
    runtimeValidationStatus: 'PARTIAL', productReleaseGate: { status: 'WARN' },
    deploymentContext: { commit: 'b1a1f8c', build: '22', branch: 'main' },
    collectorFreshness: { ageMinutes: 5 }, validationEvidence: { realIapE2E: 'DEFERRED' },
    domains: {
      IAP: { status: 'IDLE', metrics: { latencyMs: { p95: null } } },
      OPENAI: { status: 'IDLE' }, RAILWAY: { status: 'IDLE', metrics: { '5xx': 0 } },
      POSTGRES: { status: 'HEALTHY', metrics: { latencyMs: 83 } }, COLLECTOR: { status: 'HEALTHY' },
      SECURITY: { status: 'HEALTHY' }, SERVICE: { status: 'HEALTHY' },
    },
  },
  incidentState: { incidents: [] },
  incidentActions: { mode: 'LIVE', deliveryHealth: { deliveryMode: 'LIVE', deliveryHealth: 'IDLE' } },
  digestDelivery: { channel: 'slack', health: 'IDLE', mode: 'LIVE' },
  digestState: { lastDigestDeliveredWindow: '2026-08-20' },
  trend: {}, latest: {},
  events: [
    { time: '2026-08-20T14:00:00Z', domain: 'POSTGRES', event: 'postgres.probe.ok', severity: 'INFO', status: 'HEALTHY', source: 'probe' },
    { time: '2026-08-20T14:01:00Z', domain: 'INCIDENT', event: 'incident.delivery.noop', severity: 'INFO', status: 'LIVE_OK', source: 'delivery' },
  ],
};

describe('topology integrity', () => {
  test('every node has a valid category and unique id', () => {
    const ids = new Set();
    for (const n of NODES) {
      assert.ok(CATEGORIES.includes(n.category), `bad category on ${n.id}: ${n.category}`);
      assert.ok(!ids.has(n.id), `duplicate node id ${n.id}`); ids.add(n.id);
      assert.ok(typeof n.x === 'number' && typeof n.y === 'number', `${n.id} needs x/y layout`);
    }
  });
  test('no orphan edges — every edge source/target is a real node', () => {
    for (const e of EDGES) {
      assert.ok(NODE_IDS.has(e.source), `edge ${e.id} source ${e.source} is not a node`);
      assert.ok(NODE_IDS.has(e.target), `edge ${e.id} target ${e.target} is not a node`);
      assert.notEqual(e.source, e.target, `edge ${e.id} is a self-loop`);
    }
  });
  test('edge ids are unique and every edge has a real relation type', () => {
    const ids = new Set();
    const TYPES = new Set(['DATA_FLOW', 'AUTH', 'OBSERVES', 'VERIFIES', 'PERSISTS', 'EVALUATES', 'TRIGGERS', 'DELIVERS', 'DEPENDS_ON', 'SECURES', 'VALIDATION']);
    for (const e of EDGES) { assert.ok(!ids.has(e.id), `dup edge ${e.id}`); ids.add(e.id); assert.ok(TYPES.has(e.type), `bad type ${e.type} on ${e.id}`); }
  });
  test('no fully-disconnected node (every node has at least one edge)', () => {
    const connected = new Set(EDGES.flatMap((e) => [e.source, e.target]));
    for (const n of NODES) assert.ok(connected.has(n.id), `${n.id} is disconnected`);
  });
});

describe('layout + swimlane groups', () => {
  const GROUP_IDS = new Set(GROUPS.map((g) => g.id));
  test('every node belongs to a declared group and has a node size', () => {
    assert.ok(NODE_SIZE.w > 0 && NODE_SIZE.h > 0);
    for (const n of NODES) assert.ok(GROUP_IDS.has(n.group), `${n.id} has unknown group ${n.group}`);
  });
  test('no two node rectangles overlap (readable layout)', () => {
    const W = NODE_SIZE.w, H = NODE_SIZE.h;
    for (let i = 0; i < NODES.length; i++) for (let j = i + 1; j < NODES.length; j++) {
      const a = NODES[i], b = NODES[j];
      const overlap = a.x < b.x + W && a.x + W > b.x && a.y < b.y + H && a.y + H > b.y;
      assert.ok(!overlap, `nodes ${a.id} and ${b.id} overlap`);
    }
  });
  test('computeGroups returns one padded box per non-empty group wrapping its members', () => {
    const t = buildTopology({ health: null, incidentState: null, incidentActions: null, digestDelivery: null, events: [] });
    assert.equal(t.groups.length, GROUPS.length);
    for (const g of t.groups) {
      assert.ok(g.members > 0 && g.w > 0 && g.h > 0);
      const mem = t.nodes.filter((n) => n.group === g.id);
      for (const n of mem) { assert.ok(n.x >= g.x && n.x + n.w <= g.x + g.w && n.y >= g.y && n.y + n.h <= g.y + g.h, `${n.id} outside its group box`); }
    }
  });
});

describe('status normalization', () => {
  test('green / amber / red / grey buckets', () => {
    assert.equal(normalizeStatus('HEALTHY').severity, 'green');
    assert.equal(normalizeStatus('LIVE').severity, 'green');
    assert.equal(normalizeStatus('WARN').severity, 'amber');
    assert.equal(normalizeStatus('DEFERRED').severity, 'amber');
    assert.equal(normalizeStatus('IDLE').severity, 'amber');
    assert.equal(normalizeStatus('CRITICAL').severity, 'red');
    assert.equal(normalizeStatus('UNHEALTHY').severity, 'red');
    assert.equal(normalizeStatus('BLOCK').severity, 'red');
    assert.equal(normalizeStatus('UNKNOWN').severity, 'grey');
    assert.equal(normalizeStatus('NOT_CONFIGURED').severity, 'grey');
  });
  test('unknown label -> grey (never fabricated green) and null -> N/A', () => {
    assert.equal(normalizeStatus('WEIRD_STATE').severity, 'grey');
    assert.equal(normalizeStatus(null).status, 'N/A');
    assert.equal(normalizeStatus(null).severity, 'grey');
  });
});

describe('live status derivation from artifacts', () => {
  const byId = (id) => NODES.find((n) => n.id === id);
  test('domain-backed nodes read runtime-health domains', () => {
    assert.equal(statusForNode(byId('postgres'), art), 'HEALTHY');
    assert.equal(statusForNode(byId('iap_verify'), art), 'IDLE');
  });
  test('gate / deferred / incident / digest derivations', () => {
    assert.equal(statusForNode(byId('release_gate'), art), 'WARN');
    assert.equal(statusForNode(byId('real_iap_e2e'), art), 'DEFERRED');
    assert.equal(statusForNode(byId('incident_engine'), art), 'LIVE');
    assert.equal(statusForNode(byId('slack'), art), 'LIVE');
  });
  test('missing artifact -> UNKNOWN / N/A, never fabricated', () => {
    const empty = { health: null, incidentState: null, incidentActions: null, digestDelivery: null, events: [] };
    assert.equal(statusForNode(byId('postgres'), empty), 'UNKNOWN');
    assert.equal(statusForNode(byId('flutter_app'), empty), 'N/A');
  });
});

describe('graph traversal', () => {
  test('dependsOn (upstream) and usedBy (downstream) are correct for iap_verify', () => {
    const deps = dependsOn('iap_verify');
    assert.ok(deps.includes('app_store') && deps.includes('premium_product'), 'iap_verify depends on store + product');
    const used = usedBy('iap_verify');
    assert.ok(used.includes('apple_verification') && used.includes('paid_link_credits') && used.includes('collector'));
  });
  test('downstream impact of iapVerify reaches credit + release gate + incidents', () => {
    const impact = new Set(downstreamClosure('iap_verify'));
    for (const id of ['paid_link_credits', 'collector', 'evaluator', 'release_gate', 'incident_engine', 'github_issues'])
      assert.ok(impact.has(id), `iapVerify failure should reach ${id}`);
  });
  test('upstream closure of release_gate includes the observability spine', () => {
    const up = new Set(upstreamClosure('release_gate'));
    for (const id of ['runtime_health', 'evaluator', 'collector']) assert.ok(up.has(id), `gate depends on ${id}`);
  });
  test('path trace flutter_app -> paid_link_credits follows the real money path', () => {
    const path = pathTrace('flutter_app', 'paid_link_credits');
    assert.ok(path.length > 0, 'a path must exist');
    assert.equal(path[0].source, 'flutter_app');
    assert.equal(path[path.length - 1].target, 'paid_link_credits');
    const via = path.map((e) => e.source);
    assert.ok(via.includes('iap_verify'), 'money path must go through iapVerify');
  });
  test('path trace returns [] when no directed path exists', () => {
    assert.deepEqual(pathTrace('slack', 'flutter_app'), []);
  });
});

describe('incident + IAP mapping', () => {
  test('incident pipeline nodes exist and single canonical writer is modeled', () => {
    assert.ok(NODE_IDS.has('incident_engine') && NODE_IDS.has('github_issues'));
    const writers = NODES.filter((n) => n.category === 'DELIVERY' && n.id === 'github_issues');
    assert.equal(writers.length, 1, 'exactly one GitHub Issue delivery node');
    // Slack is a DELIVERY node but for digest only — no incident->slack edge may exist.
    const crossover = EDGES.find((e) => e.target === 'slack' && (e.source === 'incident_engine' || e.source === 'github_issues'));
    assert.equal(crossover, undefined, 'Slack must NOT be an incident channel (no incident->slack edge)');
  });
  test('all 7 IAP money-safety codes are represented on IAP-path nodes', () => {
    const codes = new Set(NODES.flatMap((n) => n.alertCodes || []));
    for (const c of ['IAP_SUCCESS_WITHOUT_CREDIT', 'IAP_GRANT_DELTA_NOT_ONE', 'IAP_REPLAY_DELTA_NOT_ZERO', 'IAP_CREDIT_UNKNOWN_PRODUCT', 'IAP_INVALID_PRODUCT_CREDITED', 'IAP_CREDIT_AFTER_FAILURE', 'IAP_DUPLICATE_GRANT'])
      assert.ok(codes.has(c), `money-safety code ${c} must appear on a node`);
  });
  test('real IAP E2E node stays DEFERRED', () => {
    assert.equal(statusForNode(NODES.find((n) => n.id === 'real_iap_e2e'), art), 'DEFERRED');
  });
});

describe('sanitization', () => {
  test('redacts webhook / jwt / bearer / email / api key / private key', () => {
    assert.match(redact('https://hooks.slack.com/services/T00/B00/xyzSECRET'), /REDACTED/);
    assert.match(redact('token eyJabcdefghij.klmnopqrstuv.wxyz12345'), /REDACTED_JWT/);
    assert.match(redact('Authorization: Bearer abcdef123456'), /REDACTED/);
    assert.match(redact('reach me at a.user@example.com'), /REDACTED_EMAIL/);
    assert.match(redact('key AIzaSyA1234567890123456789012345678901234'), /REDACTED_API_KEY/);
  });
  test('deepRedact walks nested structures', () => {
    const out = deepRedact({ a: { b: ['x', 'Bearer secret-token-123'] } });
    assert.match(JSON.stringify(out), /REDACTED/);
    assert.ok(!JSON.stringify(out).includes('secret-token-123'));
  });
  test('sanitizeEvent whitelists fields and drops unknown keys / PII', () => {
    const ev = sanitizeEvent({ event: 'iap.credit.granted', severity: 'INFO', domain: 'IAP', status: 'OK', source: 'verify', uid: 'abc123', email: 'x@y.com', receipt: 'BASE64BLOBBLOBBLOB' });
    assert.equal(ev.event, 'iap.credit.granted');
    assert.equal(ev.domain, 'IAP');
    assert.ok(!('uid' in ev) && !('email' in ev) && !('receipt' in ev), 'PII fields must not survive');
  });
  test('buildTopology output is fully redacted and status-normalized', () => {
    const t = buildTopology(art);
    assert.equal(t.nodes.find((n) => n.id === 'postgres').severity, 'green');
    assert.equal(t.nodes.find((n) => n.id === 'release_gate').severity, 'amber');
    assert.ok(!JSON.stringify(t).match(/hooks\.slack\.com\/services/));
  });
});

describe('assembled payloads', () => {
  test('buildMeta surfaces the global status bar fields', () => {
    const m = buildMeta(art);
    assert.equal(m.runtime, 'HEALTHY'); assert.equal(m.gate, 'WARN'); assert.equal(m.activeCritical, 0);
    assert.equal(m.commit, 'b1a1f8c'); assert.equal(m.realIapE2E, 'DEFERRED');
  });
  test('buildNodeDetail returns neighbors, impact, alert codes, runbook, sources', () => {
    const d = buildNodeDetail('postgres', art);
    assert.equal(d.status, 'HEALTHY');
    assert.ok(d.usedBy.some((x) => x.id === 'evaluator'));
    assert.ok(d.downstreamImpact.some((x) => x.id === 'release_gate'));
    assert.ok(d.alertCodes.includes('POSTGRES_CRITICAL'));
    assert.ok(d.runbook.includes('POSTGRES_UNAVAILABLE'));
    assert.ok(d.sources.length > 0);
  });
  test('unknown node id -> null', () => assert.equal(buildNodeDetail('nope', art), null));
});
