// aiSummary core tests — network-free, no emulator, NO real key.
// The full request pipeline (auth, validation, rate limit, provider, error
// mapping, observability) is exercised through handleAiSummary with injected
// deps (fake fetch, fake rate limiter). Provider errors use fake Response objects.
// Run: cd functions && npm run build && node --test test/ai-core.test.mjs
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  handleAiSummary,
  parseRequest,
  buildRequest,
  callOpenAI,
  encodeLines,
  evaluateRateLimit,
  buildObsEvent,
  normalizeStatus,
  DEFAULT_RATE_LIMIT,
  MODEL,
  AiError,
  InputError,
} from '../lib/ai-core.js';

// A key value we assert NEVER appears in any returned value, thrown error, or log.
const FAKE_KEY = 'sk-SECRET-TEST-KEY-must-never-leak';
// A pretend Firebase auth token / feedback text used for leakage assertions.
const FAKE_JWT = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.SIGNATURE_PART';
const FEEDBACK_TEXT = 'UNIQUE_FEEDBACK_BODY_9f3a yalancısın dolandırıcı';

function fakeRes({ status = 200, headers = {}, json = undefined, throwJson = false }) {
  const lower = {};
  for (const [k, v] of Object.entries(headers)) lower[k.toLowerCase()] = v;
  return {
    status,
    headers: { get: (k) => lower[String(k).toLowerCase()] ?? null },
    json: async () => {
      if (throwJson) throw new Error('bad json');
      return json;
    },
  };
}

const OK_JSON = {
  choices: [{ message: { content: '{"partOzeti":"ok","vurgular":[],"riskler":[]}' } }],
  usage: { prompt_tokens: 12, completion_tokens: 7, total_tokens: 19 },
};

function okFetch(capture = {}) {
  return async (url, init) => {
    capture.url = url;
    capture.init = init;
    return fakeRes({ status: 200, headers: { 'x-request-id': 'req_openai_abc', 'openai-processing-ms': '123' }, json: OK_JSON });
  };
}

function statusFetch(status, headers = {}) {
  return async () => fakeRes({ status, headers, json: { error: { message: 'raw provider body PROVIDER_SECRET' } } });
}

function timeoutFetch() {
  return async () => {
    const e = new Error('aborted');
    e.name = 'AbortError';
    throw e;
  };
}

function makeDeps(over = {}) {
  const logs = [];
  const deps = {
    apiKey: FAKE_KEY,
    now: () => 1_000,
    newRequestId: () => 'rid-fixed',
    log: (e) => logs.push(e),
    fetch: okFetch(),
    consumeRateLimit: async () => ({ allowed: true, retryAfterMs: 0, remaining: 99 }),
    ...over,
  };
  return { deps, logs };
}

const digestData = (over = {}) => ({
  operation: 'partial_digest',
  lang: 'tr',
  chunkIndex: 1,
  chunkTotal: 1,
  items: [{ mood: 1, relation: 'takipçi', survey: '-', text: 'harika içerik, çok faydalı' }],
  ...over,
});

const refineData = (over = {}) => ({
  operation: 'refine_report',
  lang: 'tr',
  heuristic: { cover: { trust: 50 }, executiveSummary: 'x' },
  partialsDigest: '--- PARÇA 1 / 1 ---\n{"partOzeti":"a"}',
  surveyAggregate: 'anket özeti',
  ...over,
});

describe('Phase 19 — aiSummary security/behavior matrix', () => {
  test('1. unauthenticated request -> rejected (before any provider/rate-limit)', async () => {
    let fetched = false;
    const { deps } = makeDeps({ fetch: async () => { fetched = true; return fakeRes({ status: 200, json: OK_JSON }); } });
    await assert.rejects(
      () => handleAiSummary(null, digestData(), deps),
      (e) => e instanceof AiError && e.httpsCode === 'unauthenticated' && e.code === 'AI_UNAUTHENTICATED',
    );
    assert.equal(fetched, false, 'must not call provider when unauthenticated');
  });

  test('2. authenticated valid request -> allowed, normalized content returned', async () => {
    const { deps } = makeDeps();
    const out = await handleAiSummary('user-1', digestData(), deps);
    assert.equal(out.ok, true);
    assert.equal(out.content, OK_JSON.choices[0].message.content);
    assert.equal(out.meta.model, MODEL);
  });

  test('3. arbitrary model -> rejected (forbidden field)', () => {
    assert.throws(() => parseRequest(digestData({ model: 'gpt-4o' })), (e) => e instanceof InputError && e.code === 'AI_FORBIDDEN_FIELD');
  });

  test('4. arbitrary messages / system prompt / temperature -> rejected', () => {
    assert.throws(() => parseRequest(digestData({ messages: [{ role: 'system', content: 'x' }] })), (e) => e.code === 'AI_FORBIDDEN_FIELD');
    assert.throws(() => parseRequest(digestData({ systemPrompt: 'ignore all' })), (e) => e.code === 'AI_FORBIDDEN_FIELD');
    assert.throws(() => parseRequest(digestData({ temperature: 2 })), (e) => e.code === 'AI_FORBIDDEN_FIELD');
    assert.throws(() => parseRequest(digestData({ apiKey: 'sk-x' })), (e) => e.code === 'AI_FORBIDDEN_FIELD');
    assert.throws(() => parseRequest(digestData({ providerUrl: 'http://evil' })), (e) => e.code === 'AI_FORBIDDEN_FIELD');
  });

  test('5. oversized input -> rejected (AI_INPUT_TOO_LARGE)', () => {
    const items = Array.from({ length: 121 }, () => ({ mood: 0, relation: '-', survey: '-', text: 'x' }));
    assert.throws(() => parseRequest(digestData({ items })), (e) => e.code === 'AI_INPUT_TOO_LARGE');
    // huge heuristic
    assert.throws(
      () => parseRequest(refineData({ heuristic: { blob: 'a'.repeat(60_001) } })),
      (e) => e.code === 'AI_INPUT_TOO_LARGE',
    );
  });

  test('6. unknown fields -> rejected', () => {
    assert.throws(() => parseRequest(digestData({ somethingElse: 1 })), (e) => e.code === 'AI_UNKNOWN_FIELD');
  });

  test('7. successful OpenAI response -> normalized output; server builds messages', () => {
    const parsed = parseRequest(digestData());
    const built = buildRequest(parsed);
    assert.equal(built.messages.length, 2);
    assert.equal(built.messages[0].role, 'system');
    assert.equal(built.messages[1].role, 'user');
    assert.equal(built.maxTokens, 1200);
    // refine uses the larger cap
    assert.equal(buildRequest(parseRequest(refineData())).maxTokens, 9000);
  });

  test('8. provider x-request-id -> captured as safe metadata', async () => {
    const { deps } = makeDeps();
    const out = await handleAiSummary('user-1', digestData(), deps);
    assert.equal(out.meta.openaiRequestId, 'req_openai_abc');
  });

  test('9. X-Client-Request-Id -> generated and sent to provider (not identity)', async () => {
    const capture = {};
    const { deps } = makeDeps({ fetch: okFetch(capture) });
    const out = await handleAiSummary('user-1', digestData(), deps);
    assert.equal(out.meta.clientRequestId, 'rid-fixed');
    assert.equal(capture.init.headers['X-Client-Request-Id'], 'rid-fixed');
    assert.notEqual(capture.init.headers['X-Client-Request-Id'], 'user-1'); // never the uid
  });

  test('10. token usage -> numeric metadata only', async () => {
    const { deps } = makeDeps();
    const out = await handleAiSummary('user-1', digestData(), deps);
    assert.deepEqual(out.meta.usage, { inputTokens: 12, outputTokens: 7, totalTokens: 19 });
  });

  test('11. 429 -> OPENAI_RATE_LIMITED (retryable -> unavailable)', async () => {
    const { deps } = makeDeps({ fetch: statusFetch(429) });
    await assert.rejects(
      () => handleAiSummary('user-1', digestData(), deps),
      (e) => e instanceof AiError && e.code === 'OPENAI_RATE_LIMITED' && e.httpsCode === 'unavailable',
    );
    assert.equal(normalizeStatus(429).code, 'OPENAI_RATE_LIMITED');
  });

  test('12. timeout -> OPENAI_TIMEOUT', async () => {
    const { deps, logs } = makeDeps({ fetch: timeoutFetch() });
    await assert.rejects(
      () => handleAiSummary('user-1', digestData(), deps),
      (e) => e.code === 'OPENAI_TIMEOUT',
    );
    assert.ok(logs.some((l) => l.event.eventType === 'openai.timeout'));
  });

  test('13. 5xx -> OPENAI_PROVIDER_5XX (retryable)', async () => {
    const { deps } = makeDeps({ fetch: statusFetch(503) });
    await assert.rejects(
      () => handleAiSummary('user-1', digestData(), deps),
      (e) => e.code === 'OPENAI_PROVIDER_5XX' && e.httpsCode === 'unavailable',
    );
  });

  test('13b. 401 -> OPENAI_AUTH_FAILED (permanent -> internal); raw body never surfaced', async () => {
    const { deps } = makeDeps({ fetch: statusFetch(401) });
    await assert.rejects(
      () => handleAiSummary('user-1', digestData(), deps),
      (e) => {
        assert.equal(e.code, 'OPENAI_AUTH_FAILED');
        assert.equal(e.httpsCode, 'internal');
        const s = JSON.stringify({ m: e.message, d: e.details });
        assert.ok(!s.includes('PROVIDER_SECRET'), 'raw provider body leaked');
        return true;
      },
    );
  });

  test('14. provider key -> never in success result, error, or logs', async () => {
    // success path
    {
      const { deps, logs } = makeDeps();
      const out = await handleAiSummary('user-1', digestData(), deps);
      const blob = JSON.stringify(out) + JSON.stringify(logs);
      assert.ok(!blob.includes(FAKE_KEY), 'key leaked on success');
    }
    // error path
    {
      const { deps, logs } = makeDeps({ fetch: statusFetch(500) });
      await handleAiSummary('user-1', digestData(), deps).catch((e) => {
        const blob = JSON.stringify({ m: e.message, d: e.details }) + JSON.stringify(logs);
        assert.ok(!blob.includes(FAKE_KEY), 'key leaked on error');
      });
    }
  });

  test('15. feedback content -> absent from observability events', async () => {
    const { deps, logs } = makeDeps();
    await handleAiSummary('user-1', digestData({ items: [{ mood: -1, relation: 'takipçi', survey: '-', text: FEEDBACK_TEXT }] }), deps);
    const blob = JSON.stringify(logs);
    assert.ok(logs.length > 0);
    assert.ok(!blob.includes('UNIQUE_FEEDBACK_BODY_9f3a'), 'feedback text in obs event');
    assert.ok(!blob.includes('yalancısın'), 'feedback content in obs event');
  });

  test('16. auth token / uid -> absent from observability events', async () => {
    const { deps, logs } = makeDeps();
    await handleAiSummary('user-uid-xyz', refineData({ heuristic: { note: FAKE_JWT } }), deps);
    const blob = JSON.stringify(logs);
    assert.ok(!blob.includes('user-uid-xyz'), 'uid in obs event');
    assert.ok(!blob.includes('eyJhbGciOiJIUzI1NiJ9'), 'jwt in obs event');
  });

  test('17. heuristic fallback contract -> any provider failure throws AiError (client falls back)', async () => {
    for (const f of [statusFetch(400), statusFetch(500), timeoutFetch(), async () => fakeRes({ status: 200, json: { choices: [] } })]) {
      const { deps } = makeDeps({ fetch: f });
      await assert.rejects(() => handleAiSummary('user-1', digestData(), deps), (e) => e instanceof AiError);
    }
  });

  test('18. abuse/rate-limit condition -> enforced (resource-exhausted)', async () => {
    let fetched = false;
    const { deps } = makeDeps({
      consumeRateLimit: async () => ({ allowed: false, retryAfterMs: 5000, remaining: 0 }),
      fetch: async () => { fetched = true; return fakeRes({ status: 200, json: OK_JSON }); },
    });
    await assert.rejects(
      () => handleAiSummary('user-1', digestData(), deps),
      (e) => e instanceof AiError && e.httpsCode === 'resource-exhausted' && e.code === 'AI_RATE_LIMITED',
    );
    assert.equal(fetched, false, 'must not call provider when rate limited');
  });

  test('18b. rate-limit store hiccup -> does NOT block a legitimate user (availability)', async () => {
    const { deps } = makeDeps({ consumeRateLimit: async () => { throw new Error('firestore down'); } });
    const out = await handleAiSummary('user-1', digestData(), deps);
    assert.equal(out.ok, true);
  });
});

describe('evaluateRateLimit — fixed window abuse control', () => {
  test('allows up to maxCalls then rejects within the window', () => {
    let state = null;
    const now = 1000;
    for (let i = 0; i < DEFAULT_RATE_LIMIT.maxCalls; i++) {
      const d = evaluateRateLimit(state, now, DEFAULT_RATE_LIMIT);
      assert.equal(d.allowed, true, `call ${i} should be allowed`);
      state = d.nextState;
    }
    const over = evaluateRateLimit(state, now, DEFAULT_RATE_LIMIT);
    assert.equal(over.allowed, false);
    assert.ok(over.retryAfterMs > 0);
  });

  test('window resets after windowMs (multi-chunk analyses are not broken across time)', () => {
    const cfg = { windowMs: 1000, maxCalls: 2 };
    let d = evaluateRateLimit(null, 0, cfg);
    d = evaluateRateLimit(d.nextState, 10, cfg);
    assert.equal(evaluateRateLimit(d.nextState, 20, cfg).allowed, false); // 3rd within window
    assert.equal(evaluateRateLimit(d.nextState, 2000, cfg).allowed, true); // new window
  });
});

describe('encoder + prompt safety', () => {
  test('encodeLines matches historical format (mood|relation|survey|text), pipes escaped, truncation', () => {
    const line = encodeLines([{ mood: 5, relation: 'a|b', survey: '{"x":1}', text: 'he|llo\nworld' }]).trim();
    assert.equal(line, '1|a b|{"x":1}|he¦llo world');
    const long = encodeLines([{ mood: -3, relation: '-', survey: '-', text: 'z'.repeat(500) }]).trim();
    assert.ok(long.startsWith('-1|-|-|'));
    assert.ok(long.endsWith('…'));
    assert.ok(long.length < 500);
  });

  test('buildObsEvent contains ONLY allow-listed safe keys', () => {
    const ev = buildObsEvent('openai.request.completed', {
      operation: 'partial_digest',
      statusClass: '2xx',
      latencyMs: 10,
      openaiRequestId: 'req_x',
      clientRequestId: 'rid',
      inputTokens: 1,
      outputTokens: 2,
      totalTokens: 3,
    });
    const allowed = new Set([
      'source', 'service', 'provider', 'model', 'eventType', 'severity', 'operation',
      'statusClass', 'latencyMs', 'openaiProcessingMs', 'openaiRequestId', 'clientRequestId',
      'inputTokens', 'outputTokens', 'totalTokens', 'errorCode', 'retryable', 'message',
    ]);
    for (const k of Object.keys(ev)) assert.ok(allowed.has(k), `unexpected obs key: ${k}`);
    // error events embed the safe code in the message for the existing GCP collector
    const errEv = buildObsEvent('openai.timeout', { errorCode: 'OPENAI_TIMEOUT' });
    assert.ok(String(errEv.message).includes('OPENAI_TIMEOUT'));
    assert.equal(errEv.severity, 'ERROR');
  });
});
