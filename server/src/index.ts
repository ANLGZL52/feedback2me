import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { usersRoutes } from './routes/users.js';
import { linksRoutes } from './routes/links.js';
import { feedbacksRoutes } from './routes/feedbacks.js';
import { snapshotsRoutes } from './routes/snapshots.js';
import { newCorrelationId, requestObserved, runtimeError, dbFailed, authFailed, startupError, mapErrorCode, mapAuthErrorCode, dbOpCategory } from './lib/runtime-events.js';

function resolveJwtSecret(): string | undefined {
  const raw = process.env.JWT_SECRET;
  if (raw == null) return undefined;
  const t = raw.trim();
  return t.length > 0 ? t : undefined;
}

const nodeEnv = process.env.NODE_ENV ?? 'development';
const onRailwayProduction =
  process.env.RAILWAY_ENVIRONMENT === 'production' ||
  (process.env.RAILWAY_ENVIRONMENT_NAME ?? '').toLowerCase() === 'production';
const treatAsProduction =
  nodeEnv === 'production' || onRailwayProduction;

const jwtSecret = resolveJwtSecret();

if (!jwtSecret && treatAsProduction) {
  startupError({ code: 'INTERNAL_ERROR' });
  console.error(
    'FATAL: JWT_SECRET is missing or empty in production. ' +
      'Railway: feedback2me servisi → Variables → JWT_SECRET (bu servise bağlı olsun; Raw Editor’da boş satır yok). ' +
      'Öneri: yalnızca harf+rakam; kaydettikten sonra Redeploy.',
  );
  process.exit(1);
}

// Successful-request sampling: log 100% of failures, but only every Nth success
// (and NEVER /health) so normal + health-check traffic can't flood Railway logs.
const SUCCESS_SAMPLE_N = 20;
let successCounter = 0;

export async function buildApp() {
  const app = Fastify({
    logger: !treatAsProduction,
    // Opaque per-request correlation id (NOT sequential, NOT derived from user data).
    genReqId: () => newCorrelationId(),
  });

  // PII-safe runtime events. Route TEMPLATES only (never a real code/value).
  // OBSERVATIONAL ONLY — this does NOT change any HTTP response contract.
  app.addHook('onResponse', async (request, reply) => {
    const route = request.routeOptions?.url ?? 'unmatched';
    const status = reply.statusCode;
    const cid = String(request.id);
    const ms = Math.round(reply.elapsedTime ?? 0);
    if (status >= 400) {
      requestObserved({ method: request.method, route, status, ms, cid }); // 100% of failures
    } else if (route !== '/health') {
      successCounter += 1;
      if (successCounter % SUCCESS_SAMPLE_N === 0) {
        requestObserved({ method: request.method, route, status, ms, cid }); // sampled success
      }
    }
    // Successful /health -> intentionally not logged (no flooding).
  });
  // onError is OBSERVATIONAL: it never sends a response, so the app's existing
  // error contract (route replies + Fastify's default handler) is unchanged.
  app.addHook('onError', async (request, reply, error) => {
    const cid = String(request.id);
    const route = request.routeOptions?.url;
    const code = mapErrorCode(error);
    if (code.startsWith('DB_')) dbFailed({ code, dbOp: dbOpCategory(request.method), cid });
    else runtimeError({ code, cid, route, method: request.method, status: reply.statusCode || 500 });
  });

  await app.register(cors, {
    origin: true,
    credentials: true,
  });

  await app.register(jwt, {
    secret: jwtSecret ?? 'dev-only-insecure-secret-change-in-production',
  });

  app.decorate('authenticate', async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch (e) {
      // OBSERVE the failure; the response is UNCHANGED (still 401 unauthorized).
      authFailed({ code: mapAuthErrorCode(e), route: request.routeOptions?.url, cid: String(request.id) });
      return reply.code(401).send({ error: 'unauthorized' });
    }
  });

  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(usersRoutes);
  await app.register(linksRoutes);
  await app.register(feedbacksRoutes);
  await app.register(snapshotsRoutes);

  return app;
}

const port = Number(process.env.PORT) || 8080;
const host = process.env.HOST ?? '0.0.0.0';

// Auto-start only when run as the entrypoint. Tests import buildApp() and use
// app.inject() without opening a socket (set NODE_ENV=test).
if (process.env.NODE_ENV !== 'test') {
  buildApp()
    .then((app) => {
      return app.listen({ port, host });
    })
    .then((address) => {
      console.log(`listening ${address}`);
    })
    .catch((err) => {
      startupError({ code: mapErrorCode(err) });
      console.error(err);
      process.exit(1);
    });
}
