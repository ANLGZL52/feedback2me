// Feedback2Me backend — PII-safe structured runtime events.
//
// Emits ONE JSON line per event to stdout (Railway captures it; the ops collector
// `ops/monitor/checks/railway-runtime-logs.mjs` normalizes it). There is NO public
// `emit(anyObject)` API — callers use the typed helpers below, and buildSafeEvent
// copies ONLY an allow-list of fields and redacts every string. This makes it hard
// to accidentally log a request body, feedback text, token, email, or credential.
import { randomUUID } from 'node:crypto';

const RELEASE = (process.env.RAILWAY_GIT_COMMIT_SHA ?? '').slice(0, 7) || null;

/** Redact secrets/PII from any string that would be emitted. */
export function redactStr(s: unknown): string {
  return String(s ?? '')
    .replace(/postgres(?:ql)?:\/\/[^\s"']+/gi, 'postgres://<redacted>')
    .replace(/https?:\/\/[^\s"']*:[^\s"'@]*@[^\s"']+/gi, '<redacted-url>')
    .replace(/eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '<jwt>')
    .replace(/\bBearer\s+[A-Za-z0-9._-]+/gi, 'Bearer <redacted>')
    .replace(/sk-[A-Za-z0-9]{16,}/g, '<key>')
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '<email>')
    .slice(0, 160);
}

// The ONLY fields that may ever be emitted (matches the ops collector + schema).
const FIELDS = ['evt', 'level', 'method', 'route', 'status', 'ms', 'code', 'cid', 'component', 'provider', 'dbOp', 'retryable'] as const;

export interface RuntimeEventInput {
  evt: string;
  level?: 'info' | 'warn' | 'error';
  method?: string;
  route?: string; // MUST be a route TEMPLATE (e.g. /feedbacks/:code), never a real value
  status?: number;
  ms?: number;
  code?: string;
  cid?: string;
  component?: string;
  provider?: string;
  dbOp?: string;
  retryable?: boolean;
}

/** Pure: allow-list + redact. Exported for tests. */
export function buildSafeEvent(input: RuntimeEventInput): Record<string, unknown> {
  const out: Record<string, unknown> = {
    ts: new Date().toISOString(), src: 'server', service: 'feedback2me',
    env: process.env.NODE_ENV ?? 'production', releaseSha: RELEASE,
  };
  for (const k of FIELDS) {
    const v = (input as unknown as Record<string, unknown>)[k];
    if (v === undefined || v === null) continue;
    out[k] = typeof v === 'string' ? redactStr(v) : v;
  }
  if (!out.level) out.level = 'info';
  return out;
}

function write(input: RuntimeEventInput): void {
  try { process.stdout.write(JSON.stringify(buildSafeEvent(input)) + '\n'); } catch { /* never throw from logging */ }
}

/** Opaque per-request correlation id — never derived from user data. */
export const newCorrelationId = (): string => randomUUID();

export function requestObserved(o: { method: string; route: string; status: number; ms: number; cid: string }): void {
  write({
    evt: o.status >= 400 ? 'server.request.failed' : 'server.request.completed',
    level: o.status >= 500 ? 'error' : o.status >= 400 ? 'warn' : 'info',
    method: o.method, route: o.route, status: o.status, ms: o.ms, cid: o.cid,
    component: 'node-railway-api',
  });
}
export function runtimeError(o: { code: string; cid?: string; route?: string; method?: string; status?: number }): void {
  write({ evt: 'server.runtime.error', level: 'error', code: o.code, cid: o.cid, route: o.route, method: o.method, status: o.status, component: 'node-railway-api' });
}
export function dbFailed(o: { code: string; dbOp: string; cid?: string }): void {
  write({ evt: 'db.operation.failed', level: 'error', code: o.code, dbOp: o.dbOp, cid: o.cid, component: 'node-postgres' });
}
export function authFailed(o: { code: string; route?: string; cid?: string }): void {
  write({ evt: 'auth.failed', level: 'warn', code: o.code, route: o.route, cid: o.cid, component: 'node-railway-jwt' });
}
// NOTE: this backend hosts NO AI proxy route (the /ai/chat proxy is a separate
// service), so ai.proxy.* events have no call-site here and are intentionally
// not emitted by this server.

/** Map a @fastify/jwt verify failure to a safe auth category (never the token). */
export function mapAuthErrorCode(err: unknown): string {
  const code = String((err as { code?: unknown })?.code ?? '');
  if (/NO_AUTHORIZATION/i.test(code)) return 'AUTH_MISSING';
  if (/EXPIRED/i.test(code)) return 'AUTH_EXPIRED';
  return 'AUTH_INVALID';
}

/** DB operation category from the request method (safe heuristic; never the SQL). */
export function dbOpCategory(method?: string): string {
  return method === 'GET' || method === 'HEAD' ? 'READ' : method ? 'WRITE' : 'TRANSACTION';
}
export function startupError(o: { code: string }): void {
  write({ evt: 'server.startup.error', level: 'error', code: o.code, component: 'node-railway-api' });
}

/** Map a thrown error to a STABLE safe code — never logs the raw message. */
export function mapErrorCode(err: unknown): string {
  const e = err as { code?: unknown; statusCode?: number; validation?: unknown; constructor?: { name?: string } };
  if (e && e.validation) return 'VALIDATION_ERROR';
  const name = e && e.constructor && e.constructor.name;
  if (name === 'PrismaClientInitializationError' || String(e && e.code).startsWith('P1')) return 'DB_CONNECT_FAILED';
  if (name && String(name).startsWith('PrismaClient')) return 'DB_QUERY_FAILED';
  if (e && e.statusCode === 401) return 'AUTH_INVALID';
  if (e && e.statusCode === 403) return 'AUTH_FORBIDDEN';
  return 'INTERNAL_ERROR';
}
