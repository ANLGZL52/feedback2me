import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

const addFeedbackSchema = z.object({
  linkId: z.string().min(1),
  textRaw: z.string().min(1),
  mood: z.number().int().min(-1).max(1).optional(),
  relation: z.string().max(500).nullable().optional(),
  responderName: z.string().max(200).nullable().optional(),
  creatorSurvey: z.record(z.string(), z.unknown()).nullable().optional(),
});

export const feedbacksRoutes: FastifyPluginAsync = async (app) => {
  /** Anonim gönderim — JWT opsiyonel */
  app.post('/feedbacks', async (request, reply) => {
    const parsed = addFeedbackSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', details: parsed.error.flatten() });
    }
    const { linkId, textRaw, mood, relation, responderName, creatorSurvey } = parsed.data;

    try {
      const fb = await prisma.$transaction(async (tx) => {
        const link = await tx.link.findFirst({
          where: { id: linkId, isActive: true },
        });
        if (!link) {
          throw Object.assign(new Error('link_not_found'), { code: 404 });
        }
        const now = new Date();
        if (link.validUntil && link.validUntil <= now) {
          throw Object.assign(new Error('link_expired'), { code: 410 });
        }
        if (link.linkTier === 'demo' && link.demoSubmissionUsed) {
          throw Object.assign(new Error('link_not_found'), { code: 404 });
        }

        const created = await tx.feedback.create({
          data: {
            linkId,
            textRaw: textRaw.trim(),
            mood: mood ?? null,
            relation: relation ?? null,
            responderName: responderName?.trim() || null,
            creatorSurvey: creatorSurvey ? (creatorSurvey as object) : undefined,
          },
        });

        if (link.linkTier === 'demo') {
          await tx.link.update({
            where: { id: linkId },
            data: { demoSubmissionUsed: true, isActive: false },
          });
        }

        return created;
      });

      return { feedback: feedbackToDto(fb) };
    } catch (e: unknown) {
      const err = e as { code?: number; message?: string };
      if (err.code === 404) {
        return reply.code(404).send({ error: 'link_not_found' });
      }
      if (err.code === 410) {
        return reply.code(410).send({ error: 'link_expired' });
      }
      throw e;
    }
  });

  app.get('/links/:linkId/feedbacks', { onRequest: [app.authenticate] }, async (request, reply) => {
    const ownerId = (request.user as { sub: string }).sub;
    const linkId = (request.params as { linkId: string }).linkId;

    const link = await prisma.link.findFirst({
      where: { id: linkId, ownerId },
    });
    if (!link) {
      return reply.code(404).send({ error: 'not_found' });
    }

    const list = await prisma.feedback.findMany({
      where: { linkId },
      orderBy: { createdAt: 'desc' },
    });
    return { feedbacks: list.map(feedbackToDto) };
  });

  /** Tüm aktif linklerdeki yorumlar — havuz / analiz (tarihe göre, üst limit) */
  app.get('/me/feedback-pool', { onRequest: [app.authenticate] }, async (request) => {
    const ownerId = (request.user as { sub: string }).sub;
    const limit = Math.min(Number((request.query as { limit?: string }).limit) || 200, 2000);
    const links = await prisma.link.findMany({
      where: { ownerId, isActive: true },
      select: { id: true },
    });
    const ids = links.map((l) => l.id);
    if (ids.length === 0) {
      return { feedbacks: [] };
    }
    const list = await prisma.feedback.findMany({
      where: { linkId: { in: ids } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return { feedbacks: list.map(feedbackToDto) };
  });

  app.get('/links/:linkId/feedbacks/last-at', { onRequest: [app.authenticate] }, async (request, reply) => {
    const ownerId = (request.user as { sub: string }).sub;
    const linkId = (request.params as { linkId: string }).linkId;
    const link = await prisma.link.findFirst({ where: { id: linkId, ownerId } });
    if (!link) {
      return reply.code(404).send({ error: 'not_found' });
    }
    const last = await prisma.feedback.findFirst({
      where: { linkId },
      orderBy: { createdAt: 'desc' },
      select: { createdAt: true },
    });
    return { lastFeedbackAt: last?.createdAt.toISOString() ?? null };
  });
};

function feedbackToDto(f: {
  id: string;
  linkId: string;
  responderName: string | null;
  relation: string | null;
  mood: number | null;
  textRaw: string;
  textClean: string | null;
  creatorSurvey: unknown;
  createdAt: Date;
}) {
  return {
    id: f.id,
    linkId: f.linkId,
    responderName: f.responderName,
    relation: f.relation,
    mood: f.mood,
    textRaw: f.textRaw,
    textClean: f.textClean,
    creatorSurvey: f.creatorSurvey,
    createdAt: f.createdAt.toISOString(),
  };
}
