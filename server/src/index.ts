import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { usersRoutes } from './routes/users.js';
import { linksRoutes } from './routes/links.js';
import { feedbacksRoutes } from './routes/feedbacks.js';
import { snapshotsRoutes } from './routes/snapshots.js';

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
    console.error(err);
    process.exit(1);
  });
