import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { usersRoutes } from './routes/users.js';
import { linksRoutes } from './routes/links.js';
import { feedbacksRoutes } from './routes/feedbacks.js';
import { snapshotsRoutes } from './routes/snapshots.js';
import { newCorrelationId, requestObserved, runtimeError, startupError, mapErrorCode } from './lib/runtime-events.js';

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

async function buildApp() {
  const app = Fastify({
    logger: !treatAsProduction,
    // Opaque per-request correlation id (NOT sequential, NOT derived from user data).
    genReqId: () => newCorrelationId(),
  });

  // PII-safe runtime events: one high-signal, redacted event per response, and a
  // sanitized event for any unhandled error. Route templates only (never a real
  // code/value). Does NOT re-enable Fastify's default request logging.
  app.addHook('onResponse', async (request, reply) => {
    const route = request.routeOptions?.url ?? 'unmatched';
    requestObserved({
      method: request.method,
      route,
      status: reply.statusCode,
      ms: Math.round(reply.elapsedTime ?? 0),
      cid: String(request.id),
    });
  });
  app.setErrorHandler((err, request, reply) => {
    const code = mapErrorCode(err);
    runtimeError({ code, cid: String(request.id), route: request.routeOptions?.url, method: request.method, status: reply.statusCode || 500 });
    const status = (err as { statusCode?: number }).statusCode ?? 500;
    reply.code(status).send({ error: code === 'INTERNAL_ERROR' ? 'internal_error' : code.toLowerCase() });
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
    } catch {
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
