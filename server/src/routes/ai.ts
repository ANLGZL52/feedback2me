import type { FastifyPluginAsync } from 'fastify';

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';

// Basit IP-başına rate limit (in-memory). Ölçekte Redis'e taşınabilir.
const hits = new Map<string, { n: number; t: number }>();
const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 40;

/**
 * Sunucu-tarafı OpenAI proxy: anahtar yalnızca sunucu env'inde (OPENAI_API_KEY),
 * istemciye ASLA gönderilmez. Tarayıcı CORS'unu çözer, rate-limit uygular,
 * yalnızca izin verilen alanları OpenAI'ye geçirir.
 *
 * İstemci (Flutter) dart-define: AI_PROXY_URL=https://<railway>/ai/chat
 */
export const aiRoutes: FastifyPluginAsync = async (app) => {
  app.post('/ai/chat', async (request, reply) => {
    const key = process.env.OPENAI_API_KEY;
    if (!key) {
      return reply.code(503).send({ error: 'ai_not_configured' });
    }

    // Rate limit (IP başına, kayan pencere).
    const ip = request.ip || 'unknown';
    const now = Date.now();
    const rec = hits.get(ip);
    if (!rec || now - rec.t > WINDOW_MS) {
      hits.set(ip, { n: 1, t: now });
    } else {
      rec.n += 1;
      if (rec.n > MAX_PER_WINDOW) {
        return reply.code(429).send({ error: 'rate_limited' });
      }
    }

    const b = (request.body ?? {}) as Record<string, unknown>;
    // Yalnızca izin verilen alanları geçir (istemci keyfi parametre enjekte edemez).
    const messages = Array.isArray(b.messages) ? b.messages : [];
    if (messages.length === 0) {
      return reply.code(400).send({ error: 'no_messages' });
    }
    const payload: Record<string, unknown> = {
      model: typeof b.model === 'string' ? b.model : 'gpt-4o-mini',
      messages,
      temperature: typeof b.temperature === 'number' ? b.temperature : 0.28,
      max_tokens:
        typeof b.max_tokens === 'number' ? Math.min(b.max_tokens, 9000) : 2000,
    };
    if (b.response_format) payload.response_format = b.response_format;

    try {
      const res = await fetch(OPENAI_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${key}`,
        },
        body: JSON.stringify(payload),
      });
      const text = await res.text();
      return reply
        .code(res.status)
        .header('content-type', 'application/json')
        .send(text);
    } catch {
      return reply.code(502).send({ error: 'upstream_error' });
    }
  });
};
