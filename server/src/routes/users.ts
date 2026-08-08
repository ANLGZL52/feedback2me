import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

// GÜVENLİK: kredi/premium/demo alanları İSTEMCİDEN yazılamaz (bedava-premium
// açığı). Bu alanlar yalnızca sunucu-tarafı yönetilir: kredi verme IAP
// doğrulamasıyla, demo/kredi tüketimi links.ts içindeki link oluşturma ile.
// Şemada olmayan alanlar zod tarafından atılır (strip) → sessizce yok sayılır.
const profileSchema = z.object({
  displayName: z.string().nullable().optional(),
  email: z.string().email().nullable().optional(),
  photoUrl: z.string().url().nullable().optional(),
  handle: z.string().nullable().optional(),
});

export const usersRoutes: FastifyPluginAsync = async (app) => {
  app.get('/me', { onRequest: [app.authenticate] }, async (request) => {
    const sub = (request.user as { sub: string }).sub;
    const user = await prisma.user.findUnique({ where: { id: sub } });
    if (!user) {
      return { user: null };
    }
    return { user: userToProfile(user) };
  });

  app.put('/me', { onRequest: [app.authenticate] }, async (request, reply) => {
    const sub = (request.user as { sub: string }).sub;
    const parsed = profileSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', details: parsed.error.flatten() });
    }
    const b = parsed.data;
    const user = await prisma.user.update({
      where: { id: sub },
      data: {
        ...(b.displayName !== undefined && { displayName: b.displayName }),
        ...(b.email !== undefined && { email: b.email }),
        ...(b.photoUrl !== undefined && { photoUrl: b.photoUrl }),
        ...(b.handle !== undefined && { handle: b.handle }),
      },
    });
    return { user: userToProfile(user) };
  });
};

function userToProfile(user: {
  id: string;
  email: string | null;
  displayName: string | null;
  photoUrl: string | null;
  handle: string | null;
  isPremium: boolean;
  premiumUntil: Date | null;
  freeDemoLinkUsed: boolean;
  paidLinkCredits: number;
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
    freeDemoLinkUsed: user.freeDemoLinkUsed,
    paidLinkCredits: user.paidLinkCredits,
  };
}
