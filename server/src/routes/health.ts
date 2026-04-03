import type { FastifyPluginAsync } from 'fastify';

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/health', async () => {
    return { ok: true, service: 'feedback2me-api', ts: new Date().toISOString() };
  });
};
