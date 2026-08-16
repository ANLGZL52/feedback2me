/**
 * aiSummary core — provider-independent, testable OpenAI gateway logic.
 *
 * Everything security-critical lives here so it can be unit-tested WITHOUT the
 * network, the real key, or the Firestore emulator:
 *   - the SERVER-CHOSEN model / endpoint / temperature / token limits (the client
 *     can never submit these),
 *   - the two domain operations (partial_digest, refine_report) and the exact
 *     server-side prompts (the client can never submit a system prompt / messages),
 *   - input validation + payload limits (AI_INPUT_TOO_LARGE),
 *   - the OpenAI request with an INJECTED fetch (deps.fetch) and a strict timeout,
 *   - safe provider-error normalization (never leak a raw provider body),
 *   - PII-safe observability event construction (codes/metrics only),
 *   - a bounded per-user fixed-window rate-limit decision (abuse control).
 *
 * The client sends ONLY feedback-derived content (mood/relation/survey/text and the
 * heuristic report it already built). No apiKey, model, url, messages, systemPrompt,
 * temperature — and no identity (uid/email/name/token) ever reaches OpenAI.
 */

// ---------------------------------------------------------------------------
// Server-owned provider configuration (client can NEVER influence these).
// ---------------------------------------------------------------------------
export const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
export const MODEL = 'gpt-4o-mini'; // P0 migration: DO NOT change model in this PR.
export const TEMPERATURE = 0.28;
export const CHUNK_MAX_TOKENS = 1200; // partial_digest output cap
export const REFINE_MAX_TOKENS = 9000; // refine_report output cap
export const REQUEST_TIMEOUT_MS = 60000; // server-side hard timeout per provider call

// ---------------------------------------------------------------------------
// Input limits (Phase 10 — token/cost abuse protection). Reject BEFORE OpenAI.
// ---------------------------------------------------------------------------
export const MAX_ITEMS_PER_CHUNK = 120; // client chunks at 90; 120 is a safe ceiling
export const MAX_TEXT_LEN = 420; // matches the historical encoder truncation
export const MAX_RELATION_LEN = 80;
export const MAX_SURVEY_LEN = 2000;
export const MAX_DIGEST_INPUT_CHARS = 80000; // encoded partial_digest user block
export const MAX_HEURISTIC_CHARS = 60000; // refine: heuristic JSON string
export const MAX_PARTIALS_CHARS = 120000; // refine: chunk digests
export const MAX_SURVEY_BLOCK_CHARS = 20000; // refine: survey aggregate block

// ---------------------------------------------------------------------------
// Rate limit (Phase 11 — abuse control). Fixed window, bounded storage.
// A single analysis makes N chunk calls + 1 refine call in quick succession, so
// there is intentionally NO per-call cooldown (it would break multi-chunk runs);
// the window cap is what stops "authenticated account -> unlimited OpenAI".
// ---------------------------------------------------------------------------
export interface RateLimitConfig {
  windowMs: number;
  maxCalls: number;
}
export const DEFAULT_RATE_LIMIT: RateLimitConfig = {
  windowMs: 60 * 60 * 1000, // 1 hour
  maxCalls: 120, // ~a handful of full multi-chunk analyses per hour per user
};

export interface RateWindowState {
  windowStart: number;
  count: number;
}

export interface RateLimitDecision {
  allowed: boolean;
  nextState: RateWindowState;
  retryAfterMs: number;
  remaining: number;
}

/**
 * Pure fixed-window decision. `state` is the stored window (or null/empty for a
 * first-ever call). Returns the next state to persist plus the allow verdict.
 */
export function evaluateRateLimit(
  state: RateWindowState | null | undefined,
  now: number,
  cfg: RateLimitConfig = DEFAULT_RATE_LIMIT,
): RateLimitDecision {
  const active =
    state && typeof state.windowStart === 'number' && now - state.windowStart < cfg.windowMs
      ? state
      : { windowStart: now, count: 0 };
  if (active.count >= cfg.maxCalls) {
    return {
      allowed: false,
      nextState: active,
      retryAfterMs: Math.max(0, active.windowStart + cfg.windowMs - now),
      remaining: 0,
    };
  }
  const nextState = { windowStart: active.windowStart, count: active.count + 1 };
  return {
    allowed: true,
    nextState,
    retryAfterMs: 0,
    remaining: Math.max(0, cfg.maxCalls - nextState.count),
  };
}

// ---------------------------------------------------------------------------
// Domain contract.
// ---------------------------------------------------------------------------
export type Operation = 'partial_digest' | 'refine_report';
export type Lang = 'tr' | 'en';

export interface DigestItem {
  mood: number; // -1 | 0 | 1
  relation: string;
  survey: string; // compact JSON string or '-'
  text: string;
}

/** Keys the client is ALLOWED to send. Anything else is rejected (Phase 8). */
const ALLOWED_KEYS = new Set([
  'operation',
  'lang',
  'chunkIndex',
  'chunkTotal',
  'items',
  'heuristic',
  'partialsDigest',
  'surveyAggregate',
]);

/** Keys that must NEVER be accepted from the client (provider authority). */
const FORBIDDEN_KEYS = new Set([
  'model',
  'messages',
  'system',
  'systemPrompt',
  'temperature',
  'max_tokens',
  'maxTokens',
  'apiKey',
  'api_key',
  'providerUrl',
  'url',
  'response_format',
]);

export class InputError extends Error {
  code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/** Normalize + validate the client payload. Throws InputError on any violation. */
export function parseRequest(raw: unknown): {
  operation: Operation;
  lang: Lang;
  items?: DigestItem[];
  chunkIndex: number;
  chunkTotal: number;
  heuristic?: unknown;
  partialsDigest?: string;
  surveyAggregate?: string;
} {
  if (raw == null || typeof raw !== 'object') {
    throw new InputError('AI_BAD_REQUEST', 'Geçersiz istek gövdesi.');
  }
  const data = raw as Record<string, unknown>;

  for (const k of Object.keys(data)) {
    if (FORBIDDEN_KEYS.has(k)) {
      throw new InputError('AI_FORBIDDEN_FIELD', `İzin verilmeyen alan: ${k}`);
    }
    if (!ALLOWED_KEYS.has(k)) {
      throw new InputError('AI_UNKNOWN_FIELD', `Bilinmeyen alan: ${k}`);
    }
  }

  const operation = data.operation;
  if (operation !== 'partial_digest' && operation !== 'refine_report') {
    throw new InputError('AI_BAD_OPERATION', 'Geçersiz operation.');
  }
  const lang: Lang = data.lang === 'en' ? 'en' : 'tr';

  if (operation === 'partial_digest') {
    const items = data.items;
    if (!Array.isArray(items) || items.length === 0) {
      throw new InputError('AI_BAD_REQUEST', 'items zorunlu.');
    }
    if (items.length > MAX_ITEMS_PER_CHUNK) {
      throw new InputError('AI_INPUT_TOO_LARGE', 'Parça boyutu limiti aşıldı.');
    }
    const norm: DigestItem[] = items.map((it) => {
      const o = (it ?? {}) as Record<string, unknown>;
      const moodN = Number(o.mood);
      const mood = Number.isFinite(moodN) ? Math.max(-1, Math.min(1, Math.trunc(moodN))) : 0;
      const relation = String(o.relation ?? '-').slice(0, MAX_RELATION_LEN);
      const survey = String(o.survey ?? '-').slice(0, MAX_SURVEY_LEN);
      const text = String(o.text ?? '');
      return { mood, relation, survey, text };
    });
    const encoded = encodeLines(norm);
    if (encoded.length > MAX_DIGEST_INPUT_CHARS) {
      throw new InputError('AI_INPUT_TOO_LARGE', 'Girdi boyutu limiti aşıldı.');
    }
    return {
      operation,
      lang,
      items: norm,
      chunkIndex: toInt(data.chunkIndex, 1),
      chunkTotal: toInt(data.chunkTotal, 1),
    };
  }

  // refine_report
  const heuristic = data.heuristic;
  if (heuristic == null || typeof heuristic !== 'object') {
    throw new InputError('AI_BAD_REQUEST', 'heuristic zorunlu.');
  }
  const heuristicStr = safeStringify(heuristic);
  if (heuristicStr.length > MAX_HEURISTIC_CHARS) {
    throw new InputError('AI_INPUT_TOO_LARGE', 'heuristic boyutu limiti aşıldı.');
  }
  const partialsDigest = data.partialsDigest == null ? undefined : String(data.partialsDigest);
  if (partialsDigest != null && partialsDigest.length > MAX_PARTIALS_CHARS) {
    throw new InputError('AI_INPUT_TOO_LARGE', 'partialsDigest boyutu limiti aşıldı.');
  }
  const surveyAggregate = data.surveyAggregate == null ? undefined : String(data.surveyAggregate);
  if (surveyAggregate != null && surveyAggregate.length > MAX_SURVEY_BLOCK_CHARS) {
    throw new InputError('AI_INPUT_TOO_LARGE', 'surveyAggregate boyutu limiti aşıldı.');
  }
  return {
    operation,
    lang,
    heuristic,
    partialsDigest,
    surveyAggregate,
    chunkIndex: 1,
    chunkTotal: 1,
  };
}

function toInt(v: unknown, def: number): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : def;
}

function safeStringify(v: unknown): string {
  try {
    return JSON.stringify(v) ?? '';
  } catch {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Encoder — faithful port of the historical client `_encodeLines`, so the model
// receives byte-identical input (behavior preservation).
// ---------------------------------------------------------------------------
export function encodeLines(items: DigestItem[]): string {
  const out: string[] = [];
  for (const e of items) {
    let mm = e.mood ?? 0;
    if (mm > 1) mm = 1;
    if (mm < -1) mm = -1;
    const r = (e.relation ?? '-').replace(/\|/g, ' ').trim();
    const meta = e.survey && e.survey.trim() !== '' ? e.survey : '-';
    let t = e.text.replace(/\n/g, ' ').trim();
    t = t.replace(/\|/g, '¦');
    if (t.length > MAX_TEXT_LEN) t = `${t.slice(0, MAX_TEXT_LEN)}…`;
    out.push(`${mm}|${r}|${meta}|${t}`);
  }
  return out.join('\n') + (out.length ? '\n' : '');
}

// ---------------------------------------------------------------------------
// Server-side prompts (moved off the client — the client can no longer submit
// them). Ported verbatim from the historical OpenAiAudienceClient so the AI
// summary behavior is preserved.
// ---------------------------------------------------------------------------
function systemChunkPartial(en: boolean): string {
  return en
    ? `You are a brutally honest social-media analyst. You receive ONE chunk of real follower comments.
Each line: mood|relationship|survey_json|text.

CRITICAL RULES:
1. READ EVERY COMMENT CAREFULLY. Do not generalize — extract exactly what each person said.
2. If a comment is clearly negative/hostile (insults, accusations, "you are a liar"), flag it honestly in "riskler". Do NOT soften or reframe hostility.
3. Separate genuine praise from polite/neutral comments. "Good" is not the same as "Your tutorials changed how I work".
4. For "spesifikTavsiyeler": extract any concrete suggestions about WHAT the creator should post, share, or change. Quote the commenter's actual words/ideas.
5. If comments mention specific content types (e.g. "make more tutorials", "do Q&A", "share behind-the-scenes"), capture them verbatim.
6. If the survey JSON has platform, frequency, content focus suggestions, or 1–5 scores, integrate them into highlights.
7. If text mentions audio, video, edit, lighting, cover, thumbnail, shoot, put into "uretimVeGorselNotlar".

OUTPUT SCHEMA (no other text):
{"partOzeti":"3-6 sentences; honest summary of what commenters ACTUALLY said — quote key phrases","vurgular":["specific positive points with evidence from comments"],"riskler":["specific negative signals — quote hostile/critical phrases honestly"],"spesifikTavsiyeler":["concrete content/growth suggestions extracted from comments"],"uretimVeGorselNotlar":"technical/visual notes from this chunk or empty string"}`
    : `Sen acımasızca dürüst bir sosyal medya analistisin. Sana TEK BİR PARÇA gerçek takipçi yorumu verilecek.
Her satır: mood|ilişki|anket_json|metin.

KRİTİK KURALLAR:
1. HER YORUMU DİKKATLE OKU. Genelleme yapma — her kişinin ne dediğini tam olarak çıkar.
2. Yorum açıkça olumsuz/saldırgansa (hakaret, suçlama, "yalancısın", "dolandırıcı") bunu "riskler"de DÜRÜSTÇE yaz. Düşmanlığı yumuşatma veya çerçeveleme.
3. Gerçek övgüyü kibar/nötr yorumlardan ayır. "İyi" ile "Senin sayende hayatım değişti" aynı şey değil.
4. "spesifikTavsiyeler" için: İçerik üreticisinin NE paylaşması, NE yapması veya NE değiştirmesi gerektiğine dair somut önerileri çıkar. Yorumcunun gerçek kelimelerini/fikirlerini kullan.
5. Yorumlarda spesifik içerik türleri geçiyorsa ("daha fazla tutorial yap", "Q&A yap", "sahne arkası paylaş") bunları aynen al.
6. Anket alanında platform, sıklık, içerik türü önerisi ve 1-5 puanlar varsa mutlaka özetle ve vurgularda kullan.
7. Metinlerde ses, görüntü, kurgu, ışık, kapak, thumbnail, çekim, montaj geçiyorsa bunları "uretimVeGorselNotlar"a al.

ÇIKTI ŞEMASI (başka metin yok):
{"partOzeti":"3-6 cümle; yorumcuların GERÇEKTE ne dediğinin dürüst özeti — kilit ifadeleri alıntıla","vurgular":["yorumlardan kanıtla desteklenen spesifik olumlu noktalar"],"riskler":["spesifik olumsuz sinyaller — düşmanca/eleştirel ifadeleri dürüstçe alıntıla"],"spesifikTavsiyeler":["yorumlardan çıkarılan somut içerik/büyüme önerileri"],"uretimVeGorselNotlar":"ses/görüntü/kurgu/kapak ile ilgili bu parçadan çıkan kısa özet (yoksa boş string)"}`;
}

function userChunk(en: boolean, index: number, total: number, encoded: string): string {
  return en
    ? `CHUNK ${index}/${total} — line format: mood|relationship|survey_json|text
survey_json: creator-context JSON or "-" (none). May include familiarity, platforms, watchFrequency, contentFocus, scoreProduction–scoreConsistency.
mood: 1 positive, 0 neutral, -1 negative

${encoded}`
    : `PARÇA ${index}/${total} — satır formatı: mood|ilişki|anket_json|metin
anket_json: içerik üreticisi bağlamı (JSON) veya "-" (yok). İçinde: familiarity, platforms, watchFrequency, contentFocus (izleyicinin “hangi türde daha iyi olabilir” önerisi), scoreProduction–scoreConsistency olabilir.
mood: 1 olumlu, 0 nötr, -1 olumsuz

${encoded}`;
}

function systemRefine(en: boolean): string {
  return en
    ? `You are a brutally honest content strategist and growth consultant. Task: keep all numeric fields and schema keys EXACTLY as in the input JSON, but rewrite TEXT fields based on what commenters ACTUALLY said.

CRITICAL APPROACH:
- DO NOT produce generic advice. Every recommendation must reference specific phrases, complaints, or suggestions from the chunk digests.
- If comments contain insults or accusations, acknowledge them honestly — do not sanitize.
- If there is only 1 comment, say so and note that conclusions are limited.
- Give SPECIFIC growth suggestions: "Your followers asked for X — share that to grow", "Comments suggest posting more Y format".

TEXT QUALITY:
- executiveSummary: At least 2 paragraphs. Quote or paraphrase actual comments. State what commenters literally said — praise AND criticism. If survey exists, mention.
- strategicDigest: Use "▸" sections. Each section must cite real comment evidence. Include a "▸ Specific growth actions" section with content ideas directly derived from what commenters requested or implied.
- visualAndFormatInsight: Based on actual technical mentions in comments. If nobody mentioned visuals, say "No visual feedback from commenters." Don't invent feedback.
- comprehensiveCoachLetter: Address creator directly ("you"). Be motivating but HONEST. If feedback is harsh, acknowledge it. Synthesize real quotes. Give specific next steps like "Based on comment X, try posting Y".
- topDiagnoses: Each diagnosis must reference what comments actually said, not generic themes.
- actionPlan: Every action must be derived from real comment patterns. Example: "3 commenters asked for tutorials — create a weekly tutorial series".
- segments: Describe actual audience behavior observed in comments, not theoretical segments.
- riskOpportunity: Quote actual risks from comments; opportunities based on real requests.

DO NOT CHANGE:
- cover.communityPerception, trust, contentClarity, subScores
- heatMap percentages and hint counts
- themeSignalTotal, uniqueCommentCount
- contentRecipe percent numbers
Output: a single JSON object; no markdown fences.`
    : `Sen acımasızca dürüst bir içerik stratejisti ve büyüme danışmanısın. Görevin: verilen JSON nesnesindeki
sayıları, yüzdeleri ve şema alan adlarını AYNEN KORUYARAK yalnızca METİN alanlarını yorumcuların GERÇEKTE
ne dediğine dayalı olarak yeniden yazmak.

KRİTİK YAKLAŞIM:
- Jenerik tavsiye ÜRETME. Her öneri, parça özetlerindeki gerçek ifadelere, şikayetlere veya önerilere atıfta bulunmalı.
- Yorumlar hakaret veya suçlama içeriyorsa bunu DÜRÜSTÇE kabul et — temizleme/yumuşatma yapma.
- Sadece 1 yorum varsa bunu belirt ve sonuçların sınırlı olduğunu not düş.
- SPESİFİK büyüme önerileri ver: "Takipçilerin X istemiş — bunu paylaşarak büyüyebilirsin", "Yorumlar Y formatında daha fazla içerik önerir".

ZORUNLU METİN KALİTESİ:
- executiveSummary: En az 2 paragraf. Gerçek yorumları alıntıla veya özetle. Yorumcuların birebir ne dediğini yaz — övgü VE eleştiri. Anket varsa değin.
- strategicDigest: "▸" ile bölümler. Her bölüm gerçek yorum kanıtı göstermeli. "▸ Spesifik büyüme aksiyonları" bölümü ekle: yorumcuların istediği veya ima ettiği içerik fikirlerini doğrudan buraya yaz.
- visualAndFormatInsight: Yorumlardaki gerçek teknik bahislere dayalı. Kimse görselden bahsetmediyse "Yorumculardan görsel geri bildirim gelmedi" yaz. Uydurma yapma.
- comprehensiveCoachLetter: İçerik üreticisine doğrudan hitap ("sen"). Motive edici ama DÜRÜST ol. Geri bildirim sertteyse bunu kabul et. Gerçek alıntıları sentezle. "X yorumuna göre Y paylaşmayı dene" gibi spesifik adımlar ver.
- topDiagnoses: Her teşhis yorumların GERÇEKTE ne dediğine atıf yapmalı, jenerik tema değil.
- actionPlan: Her aksiyon gerçek yorum örüntülerinden türetilmeli. Örnek: "3 yorumcu tutorial istemiş — haftalık tutorial serisi başlat".
- segments: Yorumlarda gözlemlenen gerçek kitle davranışını tanımla, teorik segmentler değil.
- riskOpportunity: Yorumlardan gerçek riskleri alıntıla; fırsatlar gerçek isteklere dayalı olsun.

KORU (dokunma):
- cover.communityPerception, trust, contentClarity, subScores
- heatMap tüm yüzdeleri ve hint sayıları
- themeSignalTotal, uniqueCommentCount
- contentRecipe içindeki percent sayıları
- Çıktı: TEK bir JSON nesnesi; ek açıklama veya markdown fence yok.`;
}

function userRefine(
  en: boolean,
  heuristic: unknown,
  partialsDigest?: string,
  surveyAggregate?: string,
): string {
  const heuristicJson = safeStringify(heuristic);
  return en
    ? `AGGREGATED SURVEY SUMMARY (all comments — do not change counts; use to enrich text):
${surveyAggregate ?? '(No or minimal survey summary.)'}

---

CHUNK DIGESTS (JSON lines; uretimVeGorselNotlar holds visual/technical hints):
${partialsDigest ?? '(No chunk digest — refine heuristic text fields only.)'}

---

HEURISTIC REPORT (JSON — preserve schema and numbers; expand text per rules above):
${heuristicJson}`
    : `TOPLU YAPISAL ANKET ÖZETİ (tüm yorumlar — sayıları değiştirme; metinleri bununla zenginleştir):
${surveyAggregate ?? '(Anket özeti yok veya çok az.)'}

---

PARÇA ÖZETLERİ (JSON satırları; uretimVeGorselNotlar alanları görsel/teknik ipuçları içerir):
${partialsDigest ?? '(Parça özeti yok — sadece heuristik JSON metinlerini iyileştir.)'}

---

HEURİSTİK RAPOR (JSON — şemayı ve sayıları koru; metin alanlarını yukarıdaki kurallarla genişlet):
${heuristicJson}`;
}

export interface ChatMessage {
  role: 'system' | 'user';
  content: string;
}

export interface BuiltRequest {
  messages: ChatMessage[];
  maxTokens: number;
}

/** Build the exact provider messages + token cap for a parsed request (server-side). */
export function buildRequest(parsed: ReturnType<typeof parseRequest>): BuiltRequest {
  const en = parsed.lang === 'en';
  if (parsed.operation === 'partial_digest') {
    const encoded = encodeLines(parsed.items!);
    return {
      messages: [
        { role: 'system', content: systemChunkPartial(en) },
        { role: 'user', content: userChunk(en, parsed.chunkIndex, parsed.chunkTotal, encoded) },
      ],
      maxTokens: CHUNK_MAX_TOKENS,
    };
  }
  return {
    messages: [
      { role: 'system', content: systemRefine(en) },
      {
        role: 'user',
        content: userRefine(en, parsed.heuristic, parsed.partialsDigest, parsed.surveyAggregate),
      },
    ],
    maxTokens: REFINE_MAX_TOKENS,
  };
}

// ---------------------------------------------------------------------------
// Provider call — injected fetch (deps.fetch) so tests never hit the network.
// ---------------------------------------------------------------------------
export interface ProviderResult {
  ok: boolean;
  content?: string;
  errorCode?: string;
  retryable: boolean;
  httpStatus: number | null;
  openaiRequestId: string | null;
  openaiProcessingMs: number | null;
  usage: { inputTokens: number | null; outputTokens: number | null; totalTokens: number | null };
  latencyMs: number;
}

export interface CallOpenAIOptions {
  apiKey: string;
  built: BuiltRequest;
  clientRequestId: string;
  now?: () => number;
  timeoutMs?: number;
}

export interface CallDeps {
  fetch?: typeof fetch;
}

const EMPTY_USAGE = { inputTokens: null, outputTokens: null, totalTokens: null };

/** Map an OpenAI HTTP status to a stable safe code (Phase 14). */
export function normalizeStatus(status: number): { code: string; retryable: boolean } {
  if (status === 401 || status === 403) return { code: 'OPENAI_AUTH_FAILED', retryable: false };
  if (status === 429) return { code: 'OPENAI_RATE_LIMITED', retryable: true };
  if (status === 400) return { code: 'OPENAI_BAD_REQUEST', retryable: false };
  if (status >= 500) return { code: 'OPENAI_PROVIDER_5XX', retryable: true };
  return { code: 'OPENAI_UNKNOWN_ERROR', retryable: false };
}

export async function callOpenAI(opts: CallOpenAIOptions, deps: CallDeps = {}): Promise<ProviderResult> {
  const doFetch = deps.fetch ?? fetch;
  const now = opts.now ?? Date.now;
  const timeoutMs = opts.timeoutMs ?? REQUEST_TIMEOUT_MS;
  const started = now();
  const body = JSON.stringify({
    model: MODEL,
    messages: opts.built.messages,
    temperature: TEMPERATURE,
    max_tokens: opts.built.maxTokens,
    response_format: { type: 'json_object' },
  });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res: Response;
  try {
    res = await doFetch(OPENAI_URL, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${opts.apiKey}`,
        'Content-Type': 'application/json',
        // Correlation only — NOT identity; safe to send to the provider.
        'X-Client-Request-Id': opts.clientRequestId,
      },
      body,
    });
  } catch (e: unknown) {
    const aborted = e instanceof Error && e.name === 'AbortError';
    return {
      ok: false,
      errorCode: aborted ? 'OPENAI_TIMEOUT' : 'OPENAI_NETWORK_ERROR',
      retryable: true,
      httpStatus: null,
      openaiRequestId: null,
      openaiProcessingMs: null,
      usage: { ...EMPTY_USAGE },
      latencyMs: now() - started,
    };
  } finally {
    clearTimeout(timer);
  }

  const openaiRequestId = safeHeader(res, 'x-request-id');
  const openaiProcessingMs = numOrNull(safeHeader(res, 'openai-processing-ms'));

  if (res.status < 200 || res.status >= 300) {
    const { code, retryable } = normalizeStatus(res.status);
    // NOTE: the raw provider error body is intentionally NOT read/returned/logged.
    return {
      ok: false,
      errorCode: code,
      retryable,
      httpStatus: res.status,
      openaiRequestId,
      openaiProcessingMs,
      usage: { ...EMPTY_USAGE },
      latencyMs: now() - started,
    };
  }

  let data: any;
  try {
    data = await res.json();
  } catch {
    return {
      ok: false,
      errorCode: 'OPENAI_INVALID_RESPONSE',
      retryable: false,
      httpStatus: res.status,
      openaiRequestId,
      openaiProcessingMs,
      usage: { ...EMPTY_USAGE },
      latencyMs: now() - started,
    };
  }

  const content = data?.choices?.[0]?.message?.content;
  const usage = {
    inputTokens: numOrNull(data?.usage?.prompt_tokens),
    outputTokens: numOrNull(data?.usage?.completion_tokens),
    totalTokens: numOrNull(data?.usage?.total_tokens),
  };
  if (typeof content !== 'string' || content.trim() === '') {
    return {
      ok: false,
      errorCode: 'OPENAI_INVALID_RESPONSE',
      retryable: false,
      httpStatus: res.status,
      openaiRequestId,
      openaiProcessingMs,
      usage,
      latencyMs: now() - started,
    };
  }

  return {
    ok: true,
    content: content.trim(),
    retryable: false,
    httpStatus: res.status,
    openaiRequestId,
    openaiProcessingMs,
    usage,
    latencyMs: now() - started,
  };
}

function safeHeader(res: Response, name: string): string | null {
  try {
    return res.headers?.get?.(name) ?? null;
  } catch {
    return null;
  }
}
function numOrNull(v: unknown): number | null {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

// ---------------------------------------------------------------------------
// Observability (Phase 13) — PII-safe structured events. Allow-listed keys only.
// NEVER prompt / feedback / completion / body / key / token / uid / email / name.
// ---------------------------------------------------------------------------
export type ObsEventType =
  | 'openai.request.completed'
  | 'openai.request.failed'
  | 'openai.rate_limited'
  | 'openai.timeout'
  | 'openai.fallback.required';

export interface ObsFields {
  operation?: Operation;
  statusClass?: string;
  latencyMs?: number | null;
  openaiProcessingMs?: number | null;
  openaiRequestId?: string | null;
  clientRequestId?: string;
  inputTokens?: number | null;
  outputTokens?: number | null;
  totalTokens?: number | null;
  errorCode?: string | null;
  retryable?: boolean;
}

const OBS_SEVERITY: Record<ObsEventType, 'INFO' | 'WARNING' | 'ERROR'> = {
  'openai.request.completed': 'INFO',
  'openai.request.failed': 'ERROR',
  'openai.rate_limited': 'WARNING',
  'openai.timeout': 'ERROR',
  'openai.fallback.required': 'WARNING',
};

/** Build one PII-safe structured event object (the ONLY thing that gets logged). */
export function buildObsEvent(eventType: ObsEventType, fields: ObsFields): Record<string, unknown> {
  const severity = OBS_SEVERITY[eventType];
  return {
    source: 'functions',
    service: 'aiSummary',
    provider: 'openai',
    model: MODEL,
    eventType,
    severity,
    operation: fields.operation ?? null,
    statusClass: fields.statusClass ?? null,
    latencyMs: fields.latencyMs ?? null,
    openaiProcessingMs: fields.openaiProcessingMs ?? null,
    openaiRequestId: fields.openaiRequestId ?? null,
    clientRequestId: fields.clientRequestId ?? null,
    inputTokens: fields.inputTokens ?? null,
    outputTokens: fields.outputTokens ?? null,
    totalTokens: fields.totalTokens ?? null,
    errorCode: fields.errorCode ?? null,
    retryable: fields.retryable ?? null,
    // NOTE: the message purposely embeds the safe errorCode so the existing
    // ops/monitor/checks/gcp-functions-logs.mjs collector (which classifies by
    // severity + message keywords) can derive FUNCTION_TIMEOUT / *_RUNTIME_ERROR.
    // The rich fields above require the SEPARATE ops-side collector update (Phase 23).
    message: `aiSummary ${eventType}${fields.errorCode ? ' ' + fields.errorCode : ''}`,
  };
}

export function statusClassOf(status: number | null): string {
  if (status == null) return 'none';
  if (status >= 500) return '5xx';
  if (status >= 400) return '4xx';
  if (status >= 300) return '3xx';
  if (status >= 200) return '2xx';
  return 'other';
}

// ---------------------------------------------------------------------------
// Orchestrated handler — the full request pipeline as a PURE, dependency-injected
// function so the entire flow (auth, validation, rate limit, provider, error
// mapping, observability) is unit-testable with no network and no emulator.
// index.ts is a thin adapter that supplies real deps (fetch, Firestore rate
// limiter, secret key, console logger) and maps AiError -> HttpsError.
// ---------------------------------------------------------------------------

/** Firebase Functions HTTPS error codes we map to (kept as strings, no SDK dep). */
export type HttpsCode =
  | 'unauthenticated'
  | 'invalid-argument'
  | 'resource-exhausted'
  | 'unavailable'
  | 'internal';

export class AiError extends Error {
  httpsCode: HttpsCode;
  code: string;
  details: Record<string, unknown>;
  constructor(httpsCode: HttpsCode, code: string, message: string, details: Record<string, unknown> = {}) {
    super(message);
    this.httpsCode = httpsCode;
    this.code = code;
    this.details = { errorCode: code, ...details };
  }
}

export interface HandlerLogEvent {
  level: 'info' | 'warn' | 'error';
  event: Record<string, unknown>;
}

export interface HandlerDeps {
  apiKey: string;
  fetch?: typeof fetch;
  /** Atomic per-user rate-limit consume (Firestore in prod; fake in tests). */
  consumeRateLimit?: (uid: string, now: number) => Promise<{ allowed: boolean; retryAfterMs: number; remaining: number }>;
  now?: () => number;
  newRequestId?: () => string;
  log?: (e: HandlerLogEvent) => void;
}

export interface AiSummarySuccess {
  ok: true;
  content: string;
  meta: {
    model: string;
    clientRequestId: string;
    openaiRequestId: string | null;
    latencyMs: number;
    usage: ProviderResult['usage'];
  };
}

/**
 * Full aiSummary pipeline. Throws AiError on any failure; index.ts translates it
 * to an HttpsError. The Flutter client treats EVERY failure as "use the heuristic
 * report", so report generation never crashes.
 */
export async function handleAiSummary(
  uid: string | null,
  data: unknown,
  deps: HandlerDeps,
): Promise<AiSummarySuccess> {
  const now = deps.now ?? Date.now;
  const newRequestId = deps.newRequestId ?? (() => 'req-fallback');
  const log = deps.log ?? (() => {});

  // 1) AUTH — identity ONLY from the verified Firebase context.
  if (!uid) {
    throw new AiError('unauthenticated', 'AI_UNAUTHENTICATED', 'Giriş gerekli.');
  }

  // 2) VALIDATE + LIMIT (no provider fields; size caps).
  let parsed;
  try {
    parsed = parseRequest(data);
  } catch (e) {
    if (e instanceof InputError) {
      throw new AiError('invalid-argument', e.code, e.message);
    }
    throw new AiError('invalid-argument', 'AI_BAD_REQUEST', 'Geçersiz istek.');
  }

  const clientRequestId = newRequestId();

  // 3) RATE LIMIT (abuse control). A store hiccup must not block a legitimate
  //    authenticated user, but it must NEVER bypass auth/validation above.
  if (deps.consumeRateLimit) {
    try {
      const rl = await deps.consumeRateLimit(uid, now());
      if (!rl.allowed) {
        log({
          level: 'warn',
          event: buildObsEvent('openai.rate_limited', {
            operation: parsed.operation,
            clientRequestId,
            errorCode: 'AI_RATE_LIMITED',
            retryable: true,
          }),
        });
        throw new AiError('resource-exhausted', 'AI_RATE_LIMITED', 'Kısa süre içinde çok fazla istek.', {
          retryAfterMs: rl.retryAfterMs,
        });
      }
    } catch (e) {
      if (e instanceof AiError) throw e;
      log({
        level: 'warn',
        event: buildObsEvent('openai.request.failed', {
          operation: parsed.operation,
          clientRequestId,
          errorCode: 'AI_RATELIMIT_STORE_UNAVAILABLE',
          retryable: true,
        }),
      });
    }
  }

  // 4) PROVIDER CALL — server-chosen model/prompt/params, injected key.
  const built = buildRequest(parsed);
  const result = await callOpenAI(
    { apiKey: deps.apiKey, built, clientRequestId, now },
    { fetch: deps.fetch },
  );

  // 5) OBSERVABILITY + RETURN.
  if (result.ok) {
    log({
      level: 'info',
      event: buildObsEvent('openai.request.completed', {
        operation: parsed.operation,
        statusClass: statusClassOf(result.httpStatus),
        latencyMs: result.latencyMs,
        openaiProcessingMs: result.openaiProcessingMs,
        openaiRequestId: result.openaiRequestId,
        clientRequestId,
        inputTokens: result.usage.inputTokens,
        outputTokens: result.usage.outputTokens,
        totalTokens: result.usage.totalTokens,
      }),
    });
    return {
      ok: true,
      content: result.content!,
      meta: {
        model: MODEL,
        clientRequestId,
        openaiRequestId: result.openaiRequestId,
        latencyMs: result.latencyMs,
        usage: result.usage,
      },
    };
  }

  // 6) SAFE ERROR NORMALIZATION — never surface the raw provider body.
  const evt = result.errorCode === 'OPENAI_TIMEOUT' ? 'openai.timeout' : 'openai.request.failed';
  log({
    level: 'error',
    event: buildObsEvent(evt, {
      operation: parsed.operation,
      statusClass: statusClassOf(result.httpStatus),
      latencyMs: result.latencyMs,
      openaiProcessingMs: result.openaiProcessingMs,
      openaiRequestId: result.openaiRequestId,
      clientRequestId,
      errorCode: result.errorCode,
      retryable: result.retryable,
    }),
  });
  const httpsCode: HttpsCode = result.retryable ? 'unavailable' : 'internal';
  throw new AiError(httpsCode, result.errorCode ?? 'OPENAI_UNKNOWN_ERROR', 'AI sağlayıcı hatası.', {
    clientRequestId,
  });
}
