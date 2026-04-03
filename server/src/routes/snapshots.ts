import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

const saveSchema = z.object({
  scores: z.object({
    overall: z.number().int(),
    positiveMomentum: z.number().int(),
    riskControl: z.number().int(),
    dataDepth: z.number().int(),
  }),
  feedbackCount: z.number().int(),
  positiveCount: z.number().int(),
  neutralCount: z.number().int(),
  negativeCount: z.number().int(),
  communityPerception: z.number().int().min(0).max(100).optional(),
  trust: z.number().int().min(0).max(100).optional(),
  contentClarity: z.number().int().min(0).max(100).optional(),
  executiveSummary: z.string().optional(),
  creatorReport: z.record(z.string(), z.unknown()).optional(),
});

export const snapshotsRoutes: FastifyPluginAsync = async (app) => {
  app.post('/audience-snapshots', { onRequest: [app.authenticate] }, async (request, reply) => {
    const userId = (request.user as { sub: string }).sub;
    const parsed = saveSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', details: parsed.error.flatten() });
    }
    const b = parsed.data;

    const snap = await prisma.$transaction(async (tx) => {
      const s = await tx.audienceScoreSnapshot.create({
        data: {
          userId,
          overallScore: b.scores.overall,
          positiveMomentum: b.scores.positiveMomentum,
          riskControl: b.scores.riskControl,
          dataDepth: b.scores.dataDepth,
          feedbackCount: b.feedbackCount,
          positiveCount: b.positiveCount,
          neutralCount: b.neutralCount,
          negativeCount: b.negativeCount,
          communityPerception: b.communityPerception ?? null,
          trust: b.trust ?? null,
          contentClarity: b.contentClarity ?? null,
          executiveSummary: b.executiveSummary?.trim() || null,
        },
      });
      if (b.creatorReport && Object.keys(b.creatorReport).length > 0) {
        await tx.audienceReportBody.create({
          data: {
            snapshotId: s.id,
            creatorReport: b.creatorReport as object,
          },
        });
      }
      return s;
    });

    return { snapshot: await loadSnapshotDtoForUser(snap.id, userId) };
  });

  app.get('/audience-snapshots', { onRequest: [app.authenticate] }, async (request) => {
    const userId = (request.user as { sub: string }).sub;
    const limit = Math.min(Number((request.query as { limit?: string }).limit) || 36, 100);
    const rows = await prisma.audienceScoreSnapshot.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    return { snapshots: rows.map((r) => snapshotLite(r)) };
  });

  app.get('/audience-snapshots/:id', { onRequest: [app.authenticate] }, async (request, reply) => {
    const userId = (request.user as { sub: string }).sub;
    const id = (request.params as { id: string }).id;
    const dto = await loadSnapshotDtoForUser(id, userId);
    if (!dto) {
      return reply.code(404).send({ error: 'not_found' });
    }
    return { snapshot: dto };
  });
};

function snapshotLite(r: {
  id: string;
  createdAt: Date;
  overallScore: number;
  positiveMomentum: number;
  riskControl: number;
  dataDepth: number;
  feedbackCount: number;
  positiveCount: number;
  neutralCount: number;
  negativeCount: number;
  communityPerception: number | null;
  trust: number | null;
  contentClarity: number | null;
  executiveSummary: string | null;
}) {
  return {
    id: r.id,
    createdAt: r.createdAt.toISOString(),
    overallScore: r.overallScore,
    positiveMomentum: r.positiveMomentum,
    riskControl: r.riskControl,
    dataDepth: r.dataDepth,
    feedbackCount: r.feedbackCount,
    positiveCount: r.positiveCount,
    neutralCount: r.neutralCount,
    negativeCount: r.negativeCount,
    communityPerception: r.communityPerception,
    trust: r.trust,
    contentClarity: r.contentClarity,
    executiveSummary: r.executiveSummary,
  };
}

async function loadSnapshotDtoForUser(id: string, userId: string | undefined) {
  const s = await prisma.audienceScoreSnapshot.findFirst({
    where: userId ? { id, userId } : { id },
    include: { reportBody: true },
  });
  if (!s) return null;

  const base = {
    id: s.id,
    createdAt: s.createdAt.toISOString(),
    scores: {
      overall: s.overallScore,
      positiveMomentum: s.positiveMomentum,
      riskControl: s.riskControl,
      dataDepth: s.dataDepth,
    },
    feedbackCount: s.feedbackCount,
    positiveCount: s.positiveCount,
    neutralCount: s.neutralCount,
    negativeCount: s.negativeCount,
    communityPerception: s.communityPerception,
    trust: s.trust,
    contentClarity: s.contentClarity,
    executiveSummary: s.executiveSummary,
    creatorReport: s.reportBody?.creatorReport ?? null,
  };
  return base;
}
