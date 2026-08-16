// Unit tests for the multi-source runtime-event merge/dedup helpers.
// Run: node --test ops/monitor/runtime-merge.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fingerprint, dedupKey, aggregateStatus, mergeEvents } from './runtime-merge.mjs';

// A normalized GCP/OpenAI event (shape produced by gcp-functions-logs.mjs).
const gcpEvent = (o = {}) => ({
  timestamp: '2026-08-16T20:08:40Z', source: 'gcp-functions', service: 'aisummary',
  eventType: 'openai.request.completed', componentId: 'node-cloud-functions', provider: 'openai',
  gcpExecutionId: 'exec-1',
  openai: { statusClass: '2xx', latencyMs: 10, clientRequestId: 'client-1', openaiRequestId: 'req-1' },
  ...o,
});
const railwayEvent = (o = {}) => ({
  timestamp: '2026-08-16T20:00:00Z', source: 'server', eventType: 'railway.http.request',
  componentId: 'node-railway-api', statusClass: '2xx', railwayRequestId: 'rw-1', ...o,
});

describe('aggregateStatus', () => {
  test('all UNKNOWN -> UNKNOWN (nothing configured)', () => {
    assert.equal(aggregateStatus(['UNKNOWN', 'UNKNOWN', 'UNKNOWN']), 'UNKNOWN');
  });
  test('any HEALTHY -> HEALTHY (an unconfigured source never forces DOWN)', () => {
    assert.equal(aggregateStatus(['UNKNOWN', 'HEALTHY', 'UNKNOWN']), 'HEALTHY');
  });
  test('a real DOWN with others UNKNOWN -> DOWN', () => {
    assert.equal(aggregateStatus(['DOWN', 'UNKNOWN', 'UNKNOWN']), 'DOWN');
  });
});

describe('dedupKey — distinct requests are not collapsed', () => {
  test('GCP: distinct openai.clientRequestId -> distinct keys', () => {
    const a = gcpEvent({ openai: { clientRequestId: 'c-A' } });
    const b = gcpEvent({ openai: { clientRequestId: 'c-B' } });
    assert.notEqual(dedupKey(a), dedupKey(b));
  });
  test('GCP: same clientRequestId + timestamp + eventType -> same key (idempotent collection)', () => {
    assert.equal(dedupKey(gcpEvent()), dedupKey(gcpEvent()));
  });
  test('GCP: no clientRequestId -> falls back to gcpExecutionId', () => {
    const a = gcpEvent({ openai: {}, gcpExecutionId: 'e-A' });
    const b = gcpEvent({ openai: {}, gcpExecutionId: 'e-B' });
    assert.notEqual(dedupKey(a), dedupKey(b));
  });
  test('Railway: correlationId/railwayRequestId still preferred', () => {
    assert.notEqual(dedupKey(railwayEvent({ railwayRequestId: 'x' })), dedupKey(railwayEvent({ railwayRequestId: 'y' })));
  });
});

describe('fingerprint — structural only (no content/PII)', () => {
  test('uses only componentId/eventType/errorCode/routeId/statusClass', () => {
    const fp = fingerprint(gcpEvent({ errorCode: null, openai: { statusClass: '4xx' } }));
    assert.equal(fp, 'node-cloud-functions|openai.request.completed|||4xx');
    // even if a (hypothetical) content field were present, fingerprint ignores it
    assert.ok(!fingerprint(gcpEvent({ prompt: 'SECRET', feedback: 'X' })).includes('SECRET'));
  });
});

describe('mergeEvents — dedup + bounded cap', () => {
  test('dedups against existing and caps to max (newest kept)', () => {
    const existing = [gcpEvent({ openai: { clientRequestId: 'c-1' } })];
    const incoming = [
      gcpEvent({ openai: { clientRequestId: 'c-1' } }), // dup of existing
      gcpEvent({ openai: { clientRequestId: 'c-2' } }),
      gcpEvent({ openai: { clientRequestId: 'c-3' } }),
    ];
    const { fresh, merged } = mergeEvents(existing, incoming, 3);
    assert.equal(fresh.length, 2); // c-2, c-3 only
    assert.equal(merged.length, 3); // capped
    assert.equal(dedupKey(merged[merged.length - 1]), dedupKey(incoming[2])); // newest retained
  });
});
