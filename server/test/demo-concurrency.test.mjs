// REST demo concurrency — gerçek DB evidence (§14-15).
// İki eşzamanlı demo submit'inin YALNIZ birinin başarılı olduğunu, DB'de tek
// feedback + demoSubmissionUsed=true kaldığını doğrular. routes/feedbacks.ts'teki
// updateMany compare-and-set pattern'ini birebir yansıtır.
//
// ÇALIŞTIRMA (Postgres gerekir — bu makinede yok, CI'da çalışır):
//   # tek seferlik test DB (örnek):
//   docker run -d --name ftm-pg -e POSTGRES_PASSWORD=pg -p 5432:5432 postgres:16
//   export DATABASE_URL="postgresql://postgres:pg@localhost:5432/postgres"
//   npm --prefix server run db:push
//   node --test server/test/demo-concurrency.test.mjs

import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

const HAS_DB = !!process.env.DATABASE_URL;

describe('REST demo concurrency (updateMany compare-and-set)', { skip: !HAS_DB ? 'DATABASE_URL yok (Postgres gerekli)' : false }, () => {
  let prisma;
  let ownerId;
  let linkId;

  before(async () => {
    const { PrismaClient } = await import('@prisma/client');
    prisma = new PrismaClient();
    const user = await prisma.user.create({
      data: { email: `conc-${Date.now()}@test.local`, freeDemoLinkUsed: true },
    });
    ownerId = user.id;
    const link = await prisma.link.create({
      data: {
        ownerId,
        code: `c${Date.now().toString(36)}`,
        linkTier: 'demo',
        isActive: true,
        demoSubmissionUsed: false,
        validUntil: new Date(Date.now() + 10 * 60 * 1000),
      },
    });
    linkId = link.id;
  });

  after(async () => {
    if (!prisma) return;
    await prisma.feedback.deleteMany({ where: { linkId } });
    await prisma.link.deleteMany({ where: { id: linkId } });
    await prisma.user.deleteMany({ where: { id: ownerId } });
    await prisma.$disconnect();
  });

  // routes/feedbacks.ts ile aynı transaction gövdesi (demo consume + feedback).
  function submitOnce(text) {
    return prisma.$transaction(async (tx) => {
      const link = await tx.link.findFirst({ where: { id: linkId, isActive: true } });
      if (!link) throw new Error('link_not_found');
      if (link.validUntil && link.validUntil <= new Date()) throw new Error('link_expired');
      if (link.linkTier === 'demo' && link.demoSubmissionUsed) throw new Error('link_not_found');
      if (link.linkTier === 'demo') {
        const consumed = await tx.link.updateMany({
          where: { id: linkId, demoSubmissionUsed: false },
          data: { demoSubmissionUsed: true, isActive: false },
        });
        if (consumed.count === 0) throw new Error('link_not_found');
      }
      return tx.feedback.create({ data: { linkId, textRaw: text } });
    });
  }

  it('iki eşzamanlı demo submit → 1 success, 1 rejection; DB: 1 feedback + consumed', async () => {
    const results = await Promise.allSettled([
      submitOnce('birinci eşzamanlı yorum'),
      submitOnce('ikinci eşzamanlı yorum'),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    const rejected = results.filter((r) => r.status === 'rejected').length;
    assert.equal(ok, 1, 'tam olarak 1 başarılı olmalı');
    assert.equal(rejected, 1, 'tam olarak 1 reddedilmeli');

    const count = await prisma.feedback.count({ where: { linkId } });
    assert.equal(count, 1, 'DB tam 1 feedback içermeli');
    const link = await prisma.link.findUnique({ where: { id: linkId } });
    assert.equal(link.demoSubmissionUsed, true);
    assert.equal(link.isActive, false);
  });
});
