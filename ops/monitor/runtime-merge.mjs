// Pure, testable helpers for merging multi-source runtime events (Railway env +
// Railway HTTP + GCP Cloud Functions) into the bounded, deduplicated, PII-safe
// runtime-events store. No I/O, no network — so collect-runtime's merge/dedup
// behavior can be unit-tested directly.

// Safe fingerprint — ONLY non-content structural fields (never feedback/prompt).
export function fingerprint(e) {
  return [e.componentId, e.eventType, e.errorCode, e.routeId, e.statusClass || (e.openai && e.openai.statusClass)].join('|');
}

// Dedup key: prefer a per-operation id so distinct requests are NOT collapsed.
// Railway: correlationId / railwayRequestId. GCP/OpenAI: openai.clientRequestId
// (a random per-op id, never identity) or the GCP execution id. Falls back to a
// (timestamp-qualified) fingerprint. timestamp is part of the key, so even
// fingerprint-keyed events from different moments stay distinct.
export function dedupKey(e) {
  const corr =
    e.correlationId ||
    e.railwayRequestId ||
    (e.openai && e.openai.clientRequestId) ||
    e.clientRequestId ||
    e.gcpExecutionId ||
    fingerprint(e);
  return [e.deploymentId, e.timestamp, e.eventType, corr].join('#');
}

// Aggregate collector statuses into one workflow status. UNKNOWN only when EVERY
// source is UNKNOWN (nothing configured); HEALTHY if any source is healthy;
// otherwise DOWN. A collector being UNKNOWN/NOT_CONFIGURED never forces DOWN.
export function aggregateStatus(statuses) {
  const list = statuses.filter(Boolean);
  if (list.length && list.every((s) => s === 'UNKNOWN')) return 'UNKNOWN';
  if (list.some((s) => s === 'HEALTHY')) return 'HEALTHY';
  return 'DOWN';
}

// Merge existing + fresh events, deduped by key, capped to `max` (newest kept).
export function mergeEvents(existing, incoming, max) {
  const seen = new Set(existing.map(dedupKey));
  const fresh = incoming.filter((e) => !seen.has(dedupKey(e)));
  const merged = [...existing, ...fresh].slice(-max);
  return { fresh, merged };
}
