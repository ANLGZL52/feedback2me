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
    try {
      const link = await prisma.$transaction(async (tx) => {
        const user = await tx.user.findUnique({ where: { id: ownerId } });
        if (!user) {
          throw Object.assign(new Error('user_not_found'), { code: 404 });
        }
        const now = new Date();
        let linkTier: string;
        let validUntil: Date;
        const userData: { freeDemoLinkUsed?: boolean; paidLinkCredits?: { decrement: number } } =
          {};

        if (!user.freeDemoLinkUsed) {
          linkTier = 'demo';
          validUntil = new Date(now.getTime() + 10 * 60 * 1000);
          userData.freeDemoLinkUsed = true;
        } else {
          const subPremium =
            user.isPremium && (!user.premiumUntil || user.premiumUntil > now);
          if (subPremium) {
            linkTier = 'premium';
            validUntil = new Date(now.getTime() + 24 * 60 * 60 * 1000);
          } else if (user.paidLinkCredits > 0) {
            linkTier = 'premium';
            validUntil = new Date(now.getTime() + 24 * 60 * 60 * 1000);
            userData.paidLinkCredits = { decrement: 1 };
          } else {
            throw Object.assign(new Error('link_requires_credit'), { code: 402 });
          }
        }

        if (Object.keys(userData).length > 0) {
          await tx.user.update({ where: { id: ownerId }, data: userData });
        }

        let code = generateLinkCode();
        for (let i = 0; i < 8; i++) {
          const exists = await tx.link.findUnique({ where: { code } });
          if (!exists) break;
          code = generateLinkCode();
        }

        return tx.link.create({
          data: {
            ownerId,
            code,
            title: parsed.data.title ?? null,
            linkTier,
            validUntil,
            demoSubmissionUsed: false,
          },
        });
      });
      return { link: linkToDto(link) };
    } catch (e: unknown) {
      const err = e as { code?: number };
      if (err.code === 402) {
        return reply.code(402).send({ error: 'link_requires_credit' });
      }
      if (err.code === 404) {
        return reply.code(404).send({ error: 'user_not_found' });
      }
      throw e;
    }
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
    const now = new Date();
    if (link.validUntil && link.validUntil <= now) {
      return reply.code(404).send({ error: 'not_found' });
    }
    if (link.linkTier === 'demo' && link.demoSubmissionUsed) {
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
  linkTier: string | null;
  validUntil: Date | null;
  demoSubmissionUsed: boolean;
}) {
  return {
    id: link.id,
    ownerId: link.ownerId,
    code: link.code,
    title: link.title,
    isActive: link.isActive,
    createdAt: link.createdAt.toISOString(),
    linkTier: link.linkTier,
    validUntil: link.validUntil?.toISOString() ?? null,
    demoSubmissionUsed: link.demoSubmissionUsed,
  };
}
