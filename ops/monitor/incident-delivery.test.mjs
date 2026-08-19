// Observability V4 — incident-delivery tests. Deterministic, no network/GitHub.
// Run: node --test ops/monitor/incident-delivery.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { computeIncidentActions, deliveryMode, willWriteFor, renderIssueBody, issueTitle, issueLabels, validateIssuePayload, RUNBOOK_SECTIONS } from './incident-actions.mjs';
import { githubIssueAdapter, findOpenIssueNumber, deliverLive } from './incident-delivery.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SLO = JSON.parse(readFileSync(join(REPO, 'ops', 'observability-slo.json'), 'utf8'));
const NOW = Date.parse('2026-08-19T12:00:00Z');
const iso = (ms) => new Date(ms).toISOString();
const min = (m) => m * 60000;

const DEP = { commit: 'abc123', build: '22' };
// Default material-change signature the engine computes for a CRITICAL alert with no
// evidence, gateStatus=null, deployment=DEP. An ONGOING fixture carrying this signature
// registers NO material change against a same-shape alert (so it won't spuriously UPDATE).
const SIG = JSON.stringify({ sev: 'CRITICAL', gate: null, deploy: DEP, ev: 0 });
const critAlert = (domain, code, extra = {}) => ({ domain, code, severity: 'CRITICAL', message: `${code} fired`, startedAt: iso(NOW - min(5)), deployContextAtStart: DEP, ...extra });
const warnAlert = (domain, code) => ({ domain, code, severity: 'WARNING', message: 'warn' });
const openInc = (domain, code, o = {}) => ({ incidentId: `${domain}:${code}`, code, domain, severity: 'CRITICAL', startedAt: iso(NOW - min(60)), lastObservedAt: iso(NOW - min(30)), resolvedAt: null, durationMs: min(30), state: 'OPEN', flapping: false, deployContextAtStart: DEP, latestDeployContext: DEP, issueNumber: 7, lastNotifiedAt: iso(NOW - min(30)), updates: [NOW - min(30)], clearedSince: null, lastSignature: SIG, flapHistory: [], runbookSection: RUNBOOK_SECTIONS[code] || null, ...o });
const run = (alerts, prevIncidents, deployment = DEP, gateStatus = null) => computeIncidentActions({ alerts, prevIncidents, config: SLO, now: NOW, deployment, gateStatus });
const act = (r, id) => r.actions.find((a) => a.incidentId === id);

describe('incident identity + NEW create', () => {
  test('NEW critical -> CREATE, OPEN, no issue yet, runbook linked', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], []);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'CREATE');
    assert.equal(a.runbookSection, 'IAP_VERIFY_DOWN');
    const inc = r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN');
    assert.equal(inc.state, 'OPEN');
    assert.equal(inc.issueNumber, null);
  });

  test('WARNING-only alerts never become incidents', () => {
    const r = run([warnAlert('OPENAI', 'OPENAI_DEGRADED'), warnAlert('VALIDATION', 'IAP_E2E_VALIDATION_DEFERRED')], []);
    assert.equal(r.actions.length, 0);
    assert.equal(r.incidents.length, 0);
  });

  test('multiple distinct criticals -> multiple CREATE', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN'), critAlert('POSTGRES', 'POSTGRES_CRITICAL')], []);
    assert.equal(r.actions.filter((a) => a.action === 'CREATE').length, 2);
  });

  test('same domain+code from a prior run dedupes to ONE incident (no second CREATE)', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN')]);
    assert.equal(r.actions.filter((a) => a.action === 'CREATE').length, 0);
    assert.equal(r.incidents.filter((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN').length, 1);
  });
});

describe('ONGOING material-change / cooldown / renotify / cap', () => {
  test('ONGOING, no material change, within renotify window -> NONE (no_material_change)', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN', { lastNotifiedAt: iso(NOW - min(40)) })]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'NONE');
    assert.equal(a.reason, 'no_material_change');
  });

  test('ONGOING past criticalRenotifyMinutes -> UPDATE (renotify_interval keep-alive)', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN', { lastNotifiedAt: iso(NOW - min(130)), updates: [NOW - min(130)] })]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'UPDATE');
    assert.equal(a.reason, 'renotify_interval');
  });

  test('material change (deploy) past cooldown -> UPDATE (material_change)', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN', { lastNotifiedAt: iso(NOW - min(40)) })], { commit: 'NEW', build: '23' });
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'UPDATE');
    assert.equal(a.reason, 'material_change');
  });

  test('material change (release gate) past cooldown -> UPDATE (material_change)', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN', { lastNotifiedAt: iso(NOW - min(40)) })], DEP, 'BLOCK');
    assert.equal(act(r, 'IAP:IAP_VERIFY_DOWN').reason, 'material_change');
  });

  test('material change but within cooldown -> NONE (cooldown), fires next cycle', () => {
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN', { lastNotifiedAt: iso(NOW - min(5)) })], { commit: 'NEW', build: '23' });
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'NONE');
    assert.equal(a.reason, 'cooldown');
    // signature is NOT advanced on suppression, so the change is still pending
    assert.equal(r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN').lastSignature, SIG);
  });

  test('update cap: >= maxIncidentUpdatesPerHour recent updates -> NONE (update_cap)', () => {
    const four = [NOW - min(50), NOW - min(40), NOW - min(20), NOW - min(5)];
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [openInc('IAP', 'IAP_VERIFY_DOWN', { lastNotifiedAt: iso(NOW - min(130)), updates: four })]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'NONE');
    assert.equal(a.reason, 'update_cap');
  });
});

describe('resolution stability', () => {
  test('cleared >= resolvedStabilityMinutes -> RESOLVE + close', () => {
    const r = run([], [openInc('IAP', 'IAP_VERIFY_DOWN', { clearedSince: iso(NOW - min(20)) })]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'RESOLVE');
    assert.equal(r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN').state, 'RESOLVED');
  });

  test('cleared but within stability grace -> NONE (pending), stays OPEN, stamps clearedSince', () => {
    const r = run([], [openInc('IAP', 'IAP_VERIFY_DOWN', { clearedSince: null })]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'NONE');
    assert.equal(a.reason, 'pending_resolution_stability');
    const inc = r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN');
    assert.equal(inc.state, 'OPEN');
    assert.equal(inc.clearedSince, iso(NOW));
  });
});

describe('flapping', () => {
  test('re-fire within flappingWindow reuses the resolved issue -> REOPEN', () => {
    const resolved = openInc('IAP', 'IAP_VERIFY_DOWN', { state: 'RESOLVED', resolvedAt: iso(NOW - min(10)), issueNumber: 42 });
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [resolved]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'REOPEN');
    assert.equal(a.issueNumber, 42);
    assert.equal(r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN').issueNumber, 42);
  });

  test('re-fire outside flappingWindow -> fresh CREATE (no reuse)', () => {
    const resolved = openInc('IAP', 'IAP_VERIFY_DOWN', { state: 'RESOLVED', resolvedAt: iso(NOW - min(90)), issueNumber: 42 });
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [resolved]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'CREATE');
    assert.equal(a.issueNumber, null);
  });

  test('resolved incident outside flapping window is pruned from state', () => {
    const resolved = openInc('IAP', 'IAP_VERIFY_DOWN', { state: 'RESOLVED', resolvedAt: iso(NOW - min(90)), issueNumber: 42 });
    const r = run([], [resolved]);
    assert.equal(r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN'), undefined);
  });

  test('resolved incident inside flapping window is retained (memory) with no action', () => {
    const resolved = openInc('IAP', 'IAP_VERIFY_DOWN', { state: 'RESOLVED', resolvedAt: iso(NOW - min(10)), issueNumber: 42 });
    const r = run([], [resolved]);
    assert.equal(r.actions.length, 0);
    assert.ok(r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN'));
  });

  test('>= flappingMinTransitions re-fires within window -> REOPEN flagged FLAPPING (one held incident)', () => {
    // 3 prior transitions in the window; this re-fire is the 4th (flappingMinTransitions=4).
    const resolved = openInc('IAP', 'IAP_VERIFY_DOWN', { state: 'RESOLVED', resolvedAt: iso(NOW - min(5)), issueNumber: 42, flapHistory: [NOW - min(45), NOW - min(30), NOW - min(15)] });
    const r = run([critAlert('IAP', 'IAP_VERIFY_DOWN')], [resolved]);
    const a = act(r, 'IAP:IAP_VERIFY_DOWN');
    assert.equal(a.action, 'REOPEN');
    assert.equal(a.flapping, true);
    assert.equal(a.reason, 'flapping');
    const inc = r.incidents.find((i) => i.incidentId === 'IAP:IAP_VERIFY_DOWN');
    assert.equal(inc.flapping, true);
    assert.equal(inc.issueNumber, 42); // still ONE incident/issue, not a new one
  });
});

describe('no-traffic vs no-observability (Phase 18)', () => {
  test('no alerts (NO_TRAFFIC / empty window) -> no incidents, no actions', () => {
    const r = run([], []);
    assert.equal(r.actions.length, 0);
    assert.equal(r.incidents.length, 0);
  });
  test('COLLECTOR_STALE critical (NO_OBSERVABILITY) -> CREATE (blindness is an incident)', () => {
    const r = run([critAlert('COLLECTOR', 'COLLECTOR_STALE')], []);
    const a = act(r, 'COLLECTOR:COLLECTOR_STALE');
    assert.equal(a.action, 'CREATE');
    assert.equal(a.runbookSection, 'COLLECTOR_STALE');
  });
  test('RAILWAY_UNREACHABLE warning (unreachable, not down) -> no incident', () => {
    const r = run([warnAlert('RAILWAY', 'RAILWAY_UNREACHABLE')], []);
    assert.equal(r.incidents.length, 0);
  });
});

describe('GitHub Issue adapter (stubbed transport — no real network)', () => {
  const inc = () => openInc('POSTGRES', 'POSTGRES_CRITICAL', { issueNumber: null, message: 'Postgres unhealthy for 3 consecutive probes' });
  const ctx = { currentRuntimeHealth: 'UNHEALTHY', productReleaseGate: 'BLOCK', runUrl: 'https://github.com/x/y/actions/runs/1' };

  test('CREATE calls gh once, parses issue number, sends only controlled labels', () => {
    const calls = [];
    const gh = (args) => { calls.push(args); return 'https://github.com/x/y/issues/123\n'; };
    const res = githubIssueAdapter(gh).apply({ action: 'CREATE' }, inc(), ctx);
    assert.equal(res.ok, true);
    assert.equal(res.issueNumber, 123);
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], 'issue'); assert.equal(calls[0][1], 'create');
    const labels = calls[0][calls[0].indexOf('--label') + 1].split(',');
    for (const l of labels) assert.ok(issueLabels(inc()).includes(l) || l === 'ops');
  });

  test('adapter error (gh throws) is swallowed -> {ok:false}, never throws', () => {
    const gh = () => { throw new Error('gh: network down'); };
    const res = githubIssueAdapter(gh).apply({ action: 'CREATE' }, inc(), ctx);
    assert.equal(res.ok, false);
    assert.match(res.error, /network down/);
  });

  test('unsafe payload (email in signal) is REJECTED before send — gh never called', () => {
    const calls = [];
    const gh = (args) => { calls.push(args); return 'issues/9'; };
    const leaky = openInc('IAP', 'IAP_VERIFY_DOWN', { issueNumber: null, message: 'user victim@example.com failed verify' });
    const res = githubIssueAdapter(gh).apply({ action: 'CREATE' }, leaky, ctx);
    assert.equal(res.ok, false);
    assert.equal(res.rejected, true);
    assert.equal(res.code, 'INCIDENT_DELIVERY_PAYLOAD_REJECTED');
    assert.equal(calls.length, 0); // nothing sent
  });

  test('REOPEN (issue already exists) reuses the issue number, does not create', () => {
    const calls = [];
    const gh = (args) => { calls.push(args[1]); return ''; };
    const res = githubIssueAdapter(gh).apply({ action: 'REOPEN' }, openInc('POSTGRES', 'POSTGRES_CRITICAL', { issueNumber: 55 }), ctx);
    assert.equal(res.ok, true);
    assert.equal(res.issueNumber, 55);
    assert.ok(calls.includes('reopen'));
    assert.ok(!calls.includes('create'));
  });
});

describe('V5 durable dedup — GitHub lookup fallback + LIVE delivery', () => {
  // Stub gh: dispatches by subcommand. `openIssues` seeds `issue list` results.
  const stub = (openIssues = [], opts = {}) => {
    const calls = [];
    const gh = (args) => {
      calls.push(args);
      if (args[0] === 'issue' && args[1] === 'list') return JSON.stringify(openIssues);
      if (args[0] === 'issue' && args[1] === 'create') { if (opts.createThrows) throw new Error('gh create failed'); return 'https://github.com/x/y/issues/501\n'; }
      return '';
    };
    return { gh, calls };
  };
  const ctx = { currentRuntimeHealth: 'UNHEALTHY', productReleaseGate: 'BLOCK', runUrl: 'https://github.com/x/y/actions/runs/1' };

  test('findOpenIssueNumber: exact-title match returns number; mismatch/none returns null', () => {
    const { gh } = stub([{ number: 88, title: '[OPS][CRITICAL] POSTGRES_CRITICAL' }]);
    assert.equal(findOpenIssueNumber(gh, 'POSTGRES_CRITICAL'), 88);
    const { gh: gh2 } = stub([{ number: 9, title: '[OPS][CRITICAL] SOMETHING_ELSE' }]);
    assert.equal(findOpenIssueNumber(gh2, 'POSTGRES_CRITICAL'), null);
  });

  test('findOpenIssueNumber: gh error is swallowed -> null', () => {
    const gh = () => { throw new Error('rate limited'); };
    assert.equal(findOpenIssueNumber(gh, 'IAP_VERIFY_DOWN'), null);
  });

  test('LIVE CREATE with NO existing issue -> creates once, records created, sets issue number', () => {
    const { gh, calls } = stub([]);
    const incidents = [openInc('POSTGRES', 'POSTGRES_CRITICAL', { issueNumber: null, message: 'unhealthy 3 probes' })];
    const actions = [{ action: 'CREATE', incidentId: 'POSTGRES:POSTGRES_CRITICAL', code: 'POSTGRES_CRITICAL', domain: 'POSTGRES' }];
    const res = deliverLive({ actions, incidents, ctx, gh, adapter: githubIssueAdapter(gh) });
    assert.equal(res.failures, 0);
    assert.ok(res.events.some((e) => e.event === 'incident.delivery.created'));
    assert.equal(incidents[0].issueNumber, 501);
    assert.equal(calls.filter((c) => c[1] === 'create').length, 1);
  });

  test('LIVE CREATE but an OPEN issue already exists -> REUSES it, NO create (dedup across lost state)', () => {
    const { gh, calls } = stub([{ number: 77, title: '[OPS][CRITICAL] POSTGRES_CRITICAL' }]);
    const incidents = [openInc('POSTGRES', 'POSTGRES_CRITICAL', { issueNumber: null, message: 'unhealthy 3 probes' })];
    const actions = [{ action: 'CREATE', incidentId: 'POSTGRES:POSTGRES_CRITICAL', code: 'POSTGRES_CRITICAL', domain: 'POSTGRES' }];
    const res = deliverLive({ actions, incidents, ctx, gh, adapter: githubIssueAdapter(gh) });
    assert.equal(calls.filter((c) => c[1] === 'create').length, 0); // never created a duplicate
    assert.equal(incidents[0].issueNumber, 77); // reused the existing issue
    assert.ok(res.events.some((e) => e.event === 'incident.delivery.updated'));
  });

  test('LIVE transport error -> failures counted, transport_error event, never throws', () => {
    const { gh } = stub([], { createThrows: true });
    const incidents = [openInc('POSTGRES', 'POSTGRES_CRITICAL', { issueNumber: null })];
    const actions = [{ action: 'CREATE', incidentId: 'POSTGRES:POSTGRES_CRITICAL', code: 'POSTGRES_CRITICAL', domain: 'POSTGRES' }];
    const res = deliverLive({ actions, incidents, ctx, gh, adapter: githubIssueAdapter(gh) });
    assert.equal(res.failures, 1);
    assert.ok(res.events.some((e) => e.event === 'incident.delivery.transport_error'));
  });

  test('LIVE unsafe payload -> rejected event, failure, gh create never called', () => {
    const { gh, calls } = stub([]);
    const incidents = [openInc('IAP', 'IAP_VERIFY_DOWN', { issueNumber: null, message: 'leak a@b.com' })];
    const actions = [{ action: 'CREATE', incidentId: 'IAP:IAP_VERIFY_DOWN', code: 'IAP_VERIFY_DOWN', domain: 'IAP' }];
    const res = deliverLive({ actions, incidents, ctx, gh, adapter: githubIssueAdapter(gh) });
    assert.equal(res.failures, 1);
    assert.ok(res.events.some((e) => e.event === 'incident.delivery.rejected_payload'));
    assert.equal(calls.filter((c) => c[1] === 'create').length, 0);
  });

  test('LIVE NONE actions are skipped -> no events, no calls', () => {
    const { gh, calls } = stub([]);
    const incidents = [openInc('IAP', 'IAP_VERIFY_DOWN')];
    const actions = [{ action: 'NONE', incidentId: 'IAP:IAP_VERIFY_DOWN', code: 'IAP_VERIFY_DOWN', reason: 'no_material_change' }];
    const res = deliverLive({ actions, incidents, ctx, gh, adapter: githubIssueAdapter(gh) });
    assert.equal(res.events.length, 0);
    assert.equal(calls.length, 0);
  });
});

describe('payload safety validator', () => {
  const safeBody = renderIssueBody(openInc('POSTGRES', 'POSTGRES_CRITICAL', { message: 'Postgres unhealthy for 3 consecutive probes' }), { currentRuntimeHealth: 'UNHEALTHY', productReleaseGate: 'BLOCK' });
  test('safe operational body passes', () => assert.equal(validateIssuePayload('[OPS][CRITICAL] POSTGRES_CRITICAL', safeBody).safe, true));
  test('email is rejected', () => assert.equal(validateIssuePayload('t', 'contact a@b.com').safe, false));
  test('bearer token is rejected', () => assert.equal(validateIssuePayload('t', 'Authorization: Bearer abc.def').safe, false));
  test('JWT is rejected', () => assert.equal(validateIssuePayload('t', 'tok eyJhbGciOiJIUzI1.eyJzdWIiOiIx').safe, false));
  test('private key header is rejected', () => assert.equal(validateIssuePayload('t', '-----BEGIN RSA PRIVATE KEY-----').safe, false));
  test('rejection carries the stable code', () => assert.equal(validateIssuePayload('t', 'a@b.com').code, 'INCIDENT_DELIVERY_PAYLOAD_REJECTED'));
});

describe('safety gate (dry-run / delivery-disabled / live)', () => {
  test('default posture (enabled=false, dryRun=true) => DRY_RUN, zero writes', () => {
    assert.equal(deliveryMode(false, true), 'DRY_RUN');
    assert.equal(willWriteFor('DRY_RUN', 'CREATE'), false);
  });
  test('enabled but still dry-run => DRY_RUN', () => assert.equal(deliveryMode(true, true), 'DRY_RUN'));
  test('not dry-run but disabled => DELIVERY_DISABLED, zero writes', () => {
    assert.equal(deliveryMode(false, false), 'DELIVERY_DISABLED');
    assert.equal(willWriteFor('DELIVERY_DISABLED', 'CREATE'), false);
  });
  test('LIVE only when enabled AND not dry-run; NONE actions never write', () => {
    assert.equal(deliveryMode(true, false), 'LIVE');
    assert.equal(willWriteFor('LIVE', 'CREATE'), true);
    assert.equal(willWriteFor('LIVE', 'NONE'), false);
  });
});

describe('PII-safe rendering', () => {
  test('issue body/title contain only operational metadata, no PII markers', () => {
    const inc = openInc('IAP', 'IAP_VERIFY_DOWN', { message: 'verify down 100% (3/3)' });
    const body = renderIssueBody(inc, { currentRuntimeHealth: 'UNHEALTHY', productReleaseGate: 'BLOCK' });
    assert.match(issueTitle(inc), /^\[OPS\]\[CRITICAL\] IAP_VERIFY_DOWN$/);
    assert.match(body, /Runbook/);
    for (const banned of ['@', 'token', 'receipt', 'uid', 'email', 'Bearer']) assert.ok(!body.toLowerCase().includes(banned.toLowerCase()), `body must not contain ${banned}`);
  });
});
