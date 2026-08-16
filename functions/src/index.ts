/**
 * FeedbackToMe — aiSummary: the trusted SERVER-SIDE OpenAI gateway.
 *
 * Why: the OpenAI key must NOT live in the Flutter client. This 2nd-gen HTTPS
 * callable holds OPENAI_API_KEY server-side (Secret Manager), verifies the
 * Firebase Auth context the client already has, enforces payload limits + a
 * per-user rate limit, and calls OpenAI with a SERVER-CHOSEN model/prompt. The
 * client sends only feedback-derived content and receives a normalized result.
 *
 * It is deliberately NOT a generic chat proxy: the client cannot submit a model,
 * a system prompt, messages, temperature, an API key, or a provider URL. The full
 * (network-free, unit-tested) pipeline lives in ai-core.ts:handleAiSummary — this
 * file only supplies real dependencies and maps AiError -> HttpsError.
 *
 * Secret (bind ONLY to this function; configure before deploy — see README):
 *   firebase functions:secrets:set OPENAI_API_KEY
 *
 * NOTE: App Check is NOT enforced yet (enforceAppCheck:false) because the Flutter
 * client does not send App Check tokens today. Firebase Auth is still required.
 * See README "App Check activation" for the safe enable path.
 */
import { onCall, HttpsError, type CallableRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import {
  handleAiSummary,
  evaluateRateLimit,
  AiError,
  DEFAULT_RATE_LIMIT,
  type HandlerLogEvent,
  type RateWindowState,
} from './ai-core.js';

// Guarded so this file merges cleanly with any other function file that also
// initializes the Admin app (e.g. a future iapVerify index).
if (!getApps().length) initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');

/**
 * Per-user fixed-window rate limit via an atomic Firestore transaction on
 * `aiUsage/{uid}`. Admin SDK writes bypass security rules, and the collection is
 * default-denied to clients (no rule grants access) — so NO firestore.rules
 * change is required.
 */
async function consumeRateLimit(
  db: Firestore,
  uid: string,
  now: number,
): Promise<{ allowed: boolean; retryAfterMs: number; remaining: number }> {
  const ref = db.collection('aiUsage').doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const state = (snap.exists ? (snap.data() as RateWindowState) : null) ?? null;
    const decision = evaluateRateLimit(state, now, DEFAULT_RATE_LIMIT);
    if (decision.allowed) {
      tx.set(ref, { windowStart: decision.nextState.windowStart, count: decision.nextState.count });
    }
    return {
      allowed: decision.allowed,
      retryAfterMs: decision.retryAfterMs,
      remaining: decision.remaining,
    };
  });
}

function emit(e: HandlerLogEvent): void {
  const line = JSON.stringify(e.event);
  if (e.level === 'error') console.error(line);
  else if (e.level === 'warn') console.warn(line);
  else console.log(line);
}

export const aiSummary = onCall(
  {
    region: 'us-central1',
    secrets: [OPENAI_API_KEY],
    enforceAppCheck: false, // client not App Check-ready yet; Firebase Auth still required
    timeoutSeconds: 240, // must exceed the 180s provider budget (ai-core REQUEST_TIMEOUT_MS)
    memory: '256MiB',
    // Cost guard: cap fan-out so a traffic burst cannot multiply OpenAI spend
    // without bound. Generous for legitimate per-user report generation.
    maxInstances: 10,
  },
  async (request: CallableRequest) => {
    try {
      return await handleAiSummary(request.auth?.uid ?? null, request.data, {
        apiKey: OPENAI_API_KEY.value(),
        consumeRateLimit: (uid, now) => consumeRateLimit(getFirestore(), uid, now),
        newRequestId: randomUUID,
        log: emit,
      });
    } catch (e) {
      if (e instanceof AiError) {
        throw new HttpsError(e.httpsCode, e.message, e.details);
      }
      // Unexpected: never leak internals.
      console.error(JSON.stringify({ source: 'functions', service: 'aiSummary', eventType: 'server.runtime.error', severity: 'ERROR', message: 'aiSummary unexpected error' }));
      throw new HttpsError('internal', 'Beklenmeyen hata.', { errorCode: 'AI_UNEXPECTED' });
    }
  },
);
