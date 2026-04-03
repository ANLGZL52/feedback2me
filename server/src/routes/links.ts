import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { generateLinkCode } from '../lib/codes.js';

const createSchema = z.object({
  title: z.string().max(200).optional(),
});

export const linksRoutes: FastifyPluginAsync = async (app) => {
  app.post('/links', { onRequest: [app.authenticate] }, async (request, reply) => {
    const ownerId = (request.user as { sub: string }).sub;
    const parsed = createSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', details: parsed.error.flatten() });
    }
    let code = generateLinkCode();
    for (let i = 0; i < 5; i++) {
      const exists = await prisma.link.findUnique({ where: { code } });
      if (!exists) break;
      code = generateLinkCode();
    }
    const link = await prisma.link.create({
      data: {
        ownerId,
        code,
        title: parsed.data.title ?? null,
      },
    });
    return { link: linkToDto(link) };
  });

  app.get('/links', { onRequest: [app.authenticate] }, async (request) => {
    const ownerId = (request.user as { sub: string }).sub;
    const links = await prisma.link.findMany({
      where: { ownerId, isActive: true },
      orderBy: { createdAt: 'desc' },
    });
    return { links: links.map(linkToDto) };
  });

  /** Misafir formu — auth yok */
  app.get('/public/links/by-code/:code', async (request, reply) => {
    const code = (request.params as { code: string }).code.toLowerCase().trim();
    const link = await prisma.link.findFirst({
      where: { code, isActive: true },
    });
    if (!link) {
      return reply.code(404).send({ error: 'not_found' });
    }
    return { link: linkToDto(link) };
  });

  app.patch('/links/:id/deactivate', { onRequest: [app.authenticate] }, async (request, reply) => {
    const ownerId = (request.user as { sub: string }).sub;
    const id = (request.params as { id: string }).id;
    const link = await prisma.link.findFirst({ where: { id, ownerId } });
    if (!link) {
      return reply.code(404).send({ error: 'not_found' });
    }
    await prisma.link.update({ where: { id }, data: { isActive: false } });
    return { ok: true };
  });
};

function linkToDto(link: {
  id: string;
  ownerId: string;
  code: string;
  title: string | null;
  isActive: boolean;
  createdAt: Date;
}) {
  return {
    id: link.id,
    ownerId: link.ownerId,
    code: link.code,
    title: link.title,
    isActive: link.isActive,
    createdAt: link.createdAt.toISOString(),
  };
}
