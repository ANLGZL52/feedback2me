// IAP production health — PURE aggregate metrics + money-safety invariants.
// Input: an array of PII-safe normalized runtime events (from
// ops/monitor/checks/gcp-functions-logs.mjs, i.e. eventType 'iap.*' with an
// allow-listed `iap` metadata object). NO network, NO secrets, NO PII.
// Money-safety invariants (A–F) are CRITICAL regardless of sample size.

const IAP_EVENTS = [
  'iap.verify.started', 'iap.verify.apple.success', 'iap.verify.apple.rejected',
  'iap.verify.apple.transient_failure', 'iap.verify.android_disabled',
  'iap.credit.granted', 'iap.credit.replay', 'iap.verify.invalid_product', 'iap.verify.error',
];
export const ALLOWED_IAP_PRODUCTS = ['premium_link_single_v2', 'premium_link_single'];

function iapOnly(events) {
  return (events || []).filter(
    (e) => e && typeof e.eventType === 'string' && e.eventType.startsWith('iap.') && IAP_EVENTS.includes(e.eventType),
  );
}
function pct(sortedAsc, p) {
  if (!sortedAsc.length) return null;
  return sortedAsc[Math.min(sortedAsc.length - 1, Math.floor(p * sortedAsc.length))];
}
const rate = (n, d) => (d > 0 ? Number((n / d).toFixed(4)) : null);

/** Safe aggregate IAP metrics (counts, rates, latency percentiles). */
export function computeIapMetrics(events) {
  const iap = iapOnly(events);
  const c = (t) => iap.filter((e) => e.eventType === t).length;
  const started = c('iap.verify.started');
  const success = c('iap.verify.apple.success');
  const rejected = c('iap.verify.apple.rejected');
  const transientFailure = c('iap.verify.apple.transient_failure');
  const error = c('iap.verify.error');
  const creditGranted = c('iap.credit.granted');
  const creditReplay = c('iap.credit.replay');
  const androidDisabled = c('iap.verify.android_disabled');
  const invalidProduct = c('iap.verify.invalid_product');

  const verifyAttempts = success + rejected + transientFailure + error; // reached Apple verification
  const lat = iap
    .map((e) => (e.iap && typeof e.iap.latencyMs === 'number' ? e.iap.latencyMs : null))
    .filter((x) => x != null)
    .sort((a, b) => a - b);

  return {
    counts: {
      started, success, rejected, transientFailure, error,
      creditGranted, creditReplay, androidDisabled, invalidProduct,
      verifyAttempts, terminal: verifyAttempts + androidDisabled + invalidProduct,
    },
    rates: {
      verifySuccess: rate(success, verifyAttempts),
      verifyFailure: rate(rejected + transientFailure + error, verifyAttempts),
      transientFailure: rate(transientFailure, verifyAttempts),
      creditGrant: rate(creditGranted, success),
      replay: rate(creditReplay, creditGranted + creditReplay),
    },
    latencyMs: { p50: pct(lat, 0.5), p95: pct(lat, 0.95), samples: lat.length },
    sampleSize: verifyAttempts + androidDisabled + invalidProduct,
  };
}

/**
 * Detect money/entitlement correctness violations (invariants A–F). Each is
 * CRITICAL. Returns [] when the ledger is consistent (or when there is no IAP
 * traffic — no traffic is NOT a violation).
 */
export function detectMoneySafetyViolations(events, allowedProducts = ALLOWED_IAP_PRODUCTS) {
  const iap = iapOnly(events);
  const allowed = new Set(allowedProducts);
  const out = [];
  const push = (code, message, evidence) => out.push({ code, severity: 'CRITICAL', message, evidence });

  // Per-event invariants: B (grant delta), C (replay delta), D (invalid credited), and
  // collect grants-per-store-correlation for F.
  const grantsByTx = new Map();
  for (const e of iap) {
    const m = e.iap || {};
    const cd = typeof m.creditDelta === 'number' ? m.creditDelta : null;
    if (e.eventType === 'iap.credit.granted') {
      if (cd !== 1) push('IAP_GRANT_DELTA_NOT_ONE', `credit.granted with creditDelta=${cd} (expected 1)`, { productId: m.productId ?? null, creditDelta: cd });
      if (m.productId && !allowed.has(m.productId)) push('IAP_CREDIT_UNKNOWN_PRODUCT', `credit.granted for non-allow-listed product '${m.productId}'`, { productId: m.productId });
      if (m.txCorrelation) grantsByTx.set(m.txCorrelation, (grantsByTx.get(m.txCorrelation) || 0) + 1);
    } else if (e.eventType === 'iap.credit.replay') {
      if (cd !== 0) push('IAP_REPLAY_DELTA_NOT_ZERO', `credit.replay with creditDelta=${cd} (expected 0)`, { productId: m.productId ?? null, creditDelta: cd });
    } else if (e.eventType === 'iap.verify.invalid_product' && cd != null && cd > 0) {
      push('IAP_INVALID_PRODUCT_CREDITED', `invalid_product event carried creditDelta=${cd} (expected 0)`, { creditDelta: cd });
    }
  }
  // F: the SAME store-authoritative purchase (txCorrelation) granted more than once.
  for (const [tx, n] of grantsByTx) {
    if (n > 1) push('IAP_DUPLICATE_GRANT', `${n} credit.granted events share one store correlation (idempotency breach)`, { txCorrelation: tx, grants: n });
  }

  // Per-operation invariants A + E: correlate a single verify op via clientRequestId.
  const byReq = new Map();
  for (const e of iap) {
    const id = e.iap && e.iap.clientRequestId;
    if (!id) continue;
    if (!byReq.has(id)) byReq.set(id, new Set());
    byReq.get(id).add(e.eventType);
  }
  for (const [id, types] of byReq) {
    const hasSuccess = types.has('iap.verify.apple.success');
    const hasGrant = types.has('iap.credit.granted');
    const hasReplay = types.has('iap.credit.replay');
    const hasFailure = types.has('iap.verify.apple.rejected') || types.has('iap.verify.apple.transient_failure') || types.has('iap.verify.error');
    // A: Apple verification SUCCESS but no committed credit result (grant OR replay).
    // (Verify + grant are emitted in the same request, so within one collection window.)
    if (hasSuccess && !hasGrant && !hasReplay) push('IAP_SUCCESS_WITHOUT_CREDIT', 'Apple verification SUCCESS with no committed credit.granted/replay in the same operation', { clientRequestId: id });
    // E: a verification FAILURE yet a credit was granted for the same operation.
    if (hasFailure && hasGrant) push('IAP_CREDIT_AFTER_FAILURE', 'credit.granted in an operation that also emitted a verification FAILURE', { clientRequestId: id });
  }
  return out;
}
