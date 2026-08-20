// Read-only topology dashboard — SANITIZER. Nothing leaves the API until it passes
// through here. Redacts anything secret/PII-shaped and whitelists event fields. This is a
// defense-in-depth layer on TOP of the ops pipeline's own PII-safety (events are already
// allow-listed at emit time); the dashboard must never be the place a secret leaks.

const REDACTIONS = [
  [/https:\/\/hooks\.slack\.com\/services\/[^\s"']+/gi, '[REDACTED_SLACK_WEBHOOK]'],
  [/https:\/\/hooks\.slack\.test\/[^\s"']+/gi, '[REDACTED_WEBHOOK]'],
  [/xox[baprs]-[A-Za-z0-9-]+/g, '[REDACTED_SLACK_TOKEN]'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, '[REDACTED_PRIVATE_KEY]'],
  [/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}/g, '[REDACTED_JWT]'],
  [/\bBearer\s+[A-Za-z0-9._-]+/gi, '[REDACTED_BEARER]'],
  [/\bAuthorization\s*[:=]\s*\S+/gi, '[REDACTED_AUTH]'],
  [/AIza[0-9A-Za-z_-]{30,}/g, '[REDACTED_API_KEY]'],
  [/sk-[A-Za-z0-9]{20,}/g, '[REDACTED_API_KEY]'],
  [/\bgh[pousr]_[A-Za-z0-9]{20,}/g, '[REDACTED_GH_TOKEN]'],
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[REDACTED_EMAIL]'],
  // long opaque blobs (base64-ish) that could be a receipt / token
  [/\b[A-Za-z0-9+/]{60,}={0,2}\b/g, '[REDACTED_BLOB]'],
];

export function redact(value) {
  if (typeof value !== 'string') return value;
  let out = value;
  for (const [re, sub] of REDACTIONS) out = out.replace(re, sub);
  return out;
}

// Deep-redact any string found anywhere in an object/array. Non-destructive (returns a copy).
export function deepRedact(v) {
  if (typeof v === 'string') return redact(v);
  if (Array.isArray(v)) return v.map(deepRedact);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, val] of Object.entries(v)) o[k] = deepRedact(val);
    return o;
  }
  return v;
}

// Normalize + whitelist a single operational event into EXACTLY the 6 UI fields. Tolerant of
// the real ops schemas: component-check events (checkId/status/componentId) and runtime
// events (eventType/componentId/source). No field other than the six below ever reaches the UI.
export function sanitizeEvent(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const time = raw.time || raw.timestamp || null;
  // event name: explicit event/code, else eventType, else checkId, else a status label.
  const name = raw.event || raw.code || raw.eventType || raw.checkId || (raw.status ? `check.${String(raw.status).toLowerCase()}` : null);
  if (!name) return null;
  const domainHint = [raw.domain, raw.componentId, raw.checkId, raw.eventType, raw.service, raw.source].filter(Boolean).join(' ');
  const status = raw.status != null ? String(raw.status).toUpperCase().slice(0, 24) : null;
  return {
    time: time || null,
    domain: normalizeDomain(domainHint),
    event: redact(String(name)).slice(0, 120),
    severity: normalizeSeverity(raw.severity, status),
    status,
    source: redact(String(raw.source || raw.checkId || 'ops')).slice(0, 40),
  };
}

function normalizeSeverity(sev, status) {
  const s = (sev == null ? '' : String(sev)).toUpperCase();
  if (s.startsWith('CRIT') || s === 'ERROR' || s === 'FATAL') return 'CRITICAL';
  if (s.startsWith('WARN')) return 'WARNING';
  if (s === 'INFO' || s === 'INFORMATIONAL' || s === 'DEBUG' || s === 'NOTICE') return 'INFO';
  // derive from status when severity is absent/null
  const st = (status || '').toUpperCase();
  if (['DOWN', 'UNHEALTHY', 'CRITICAL', 'BLOCK', 'FAILED'].includes(st)) return 'CRITICAL';
  if (['DEGRADED', 'WARN', 'WARNING', 'PARTIAL'].includes(st)) return 'WARNING';
  return 'INFO';
}

function normalizeDomain(hint) {
  const up = String(hint || '').toUpperCase();
  if (/\bIAP\b|VERIFY|PURCHASE|CREDIT|APPLE|STOREKIT/.test(up)) return 'IAP';
  if (/OPENAI|\bAI\b|SUMMARY/.test(up)) return 'OPENAI';
  if (/RAILWAY/.test(up)) return 'RAILWAY';
  if (/POSTGRES|\bPG\b/.test(up)) return 'POSTGRES';
  if (/COLLECT/.test(up)) return 'COLLECTOR';
  if (/INCIDENT|ALERT/.test(up)) return 'INCIDENT';
  if (/SLACK|DIGEST/.test(up)) return 'SLACK';
  if (/SECRET|PII|WIF|GCP|SECURITY/.test(up)) return 'SECURITY';
  if (/SERVICE|HOSTING|FHTML|FIREBASE|FIRESTORE|COMPONENT|NODE-/.test(up)) return 'SERVICE';
  return 'OTHER';
}
