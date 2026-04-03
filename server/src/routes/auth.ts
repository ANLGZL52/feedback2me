import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

const devLoginSchema = z.object({
  email: z.string().email(),
  displayName: z.string().optional(),
});

/**
 * Geliştirme / staging: gerçek OAuth olmadan JWT üretir.
 * Production'da ALLOW_DEV_AUTH=true yapma; yerine Google/Apple token doğrulama eklenecek.
 */
export const authRoutes: FastifyPluginAsync = async (app) => {
  app.post('/auth/dev/login', async (request, reply) => {
    if (process.env.ALLOW_DEV_AUTH !== 'true') {
      return reply.code(404).send({ error: 'not_found' });
    }
    const raw = request.headers['x-dev-secret'];
    const secret = Array.isArray(raw) ? raw[0] : raw;
    if (!secret || secret !== process.env.DEV_AUTH_SECRET) {
      return reply.code(401).send({ error: 'unauthorized' });
    }
    const parsed = devLoginSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', details: parsed.error.flatten() });
    }
    const { email, displayName } = parsed.data;

    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          displayName: displayName ?? email.split('@')[0],
        },
      });
    }

    const token = await reply.jwtSign({ sub: user.id });
    return {
      accessToken: token,
      user: userToDto(user),
    };
  });
};

function userToDto(user: {
  id: string;
  email: string | null;
  displayName: string | null;
  photoUrl: string | null;
  handle: string | null;
  isPremium: boolean;
  premiumUntil: Date | null;
  createdAt: Date;
}) {
  return {
    uid: user.id,
    displayName: user.displayName,
    email: user.email,
    photoUrl: user.photoUrl,
    handle: user.handle,
    isPremium: user.isPremium,
    premiumUntil: user.premiumUntil?.toISOString() ?? null,
    createdAt: user.createdAt.toISOString(),
  };
}
