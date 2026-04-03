import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { usersRoutes } from './routes/users.js';
import { linksRoutes } from './routes/links.js';
import { feedbacksRoutes } from './routes/feedbacks.js';
import { snapshotsRoutes } from './routes/snapshots.js';

const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret && process.env.NODE_ENV === 'production') {
  console.error('FATAL: JWT_SECRET is required in production');
  process.exit(1);
}

async function buildApp() {
  const app = Fastify({
    logger: process.env.NODE_ENV === 'development',
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
