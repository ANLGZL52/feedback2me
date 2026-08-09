# FeedbackToMe API (Railway backend)

PostgreSQL + Prisma + Fastify. Flutter uygulamasındaki Firestore işlemlerinin REST karşılığı (kademeli taşıma).

## Gereksinimler

- Node 20+
- PostgreSQL 15+

## Kurulum (yerel)

```bash
cd server
cp .env.example .env
# DATABASE_URL ve JWT_SECRET doldur
npm install
npx prisma db push
npm run dev
```

- Sağlık: `GET http://localhost:8080/health`
- Geliştirme girişi (`.env`: `ALLOW_DEV_AUTH=true`, `DEV_AUTH_SECRET=...`):

```http
POST /auth/dev/login
X-Dev-Secret: <.env içindeki DEV_AUTH_SECRET ile aynı>
Content-Type: application/json

{"email":"test@test.com","displayName":"Test"}
```

Yanıttaki `accessToken` ile:

```http
Authorization: Bearer <accessToken>
GET /me
```

## Önemli uçlar

| Metot | Yol | Auth |
|-------|-----|------|
| GET | `/health` | Hayır |
| POST | `/auth/dev/login` | Dev secret |
| GET/PUT | `/me` | JWT |
| POST | `/links` | JWT |
| GET | `/links` | JWT |
| GET | `/public/links/by-code/:code` | Hayır |
| PATCH | `/links/:id/deactivate` | JWT |
| POST | `/feedbacks` | Hayır (misafir) |
| GET | `/links/:linkId/feedbacks` | JWT (sahip) |
| GET | `/me/feedback-pool` | JWT |
| POST/GET | `/audience-snapshots` | JWT |
| POST | `/ai/chat` | Hayır (IP rate-limit) — OpenAI proxy |

## Railway

1. Yeni servis → **GitHub repo** → root directory: **`server`** (veya monorepo kökünde Dockerfile path ayarla).
2. **PostgreSQL** ekle; `DATABASE_URL` API servisine bağlanır (Reference variables).
3. **Variables** (bu **API servisinin** sekmesinde): `JWT_SECRET` (boş olamaz; sadece ASCII önerilir), `NODE_ENV`=`production`, isteğe bağlı `ALLOW_DEV_AUTH` / `DEV_AUTH_SECRET`. Değişken yalnızca proje düzeyindeyse konteynere gelmeyebilir — servise ekleyin ve **Redeploy** yapın.
4. **Build:** `npm ci && npm run build` veya Dockerfile kullan.
5. **Start:** `node dist/index.js` — `PORT` Railway tarafından verilir.

## AI proxy (P0.1) — anahtar istemciden kalkar

`POST /ai/chat` sunucu-tarafı OpenAI proxy'sidir: OpenAI anahtarı **yalnızca
sunucu env'inde** (`OPENAI_API_KEY`), istemciye asla gönderilmez. Rate-limit
(IP başına 40/dk) + yalnızca izinli alanların geçişi vardır.

İstemci (`OpenAiAudienceClient`) artık **yalnızca bu proxy'yi** çağırır; gömülü
anahtar veya doğrudan OpenAI çağrısı **yoktur**. Proxy verilmezse AI kapalı sayılır
ve topluluk özeti **sezgisel yedeğe** düşer (uygulama kırılmaz).

**Kurulum:**
1. **Sunucu (Railway):** API servisine `OPENAI_API_KEY` değişkenini ekle → **Redeploy**.
   Doğrula: `POST https://<host>/ai/chat` anahtarsızken 503, anahtarla 200.
2. **İstemci derlemesi:** proxy URL'ini dart-define ile ver:
   ```bash
   flutter build appbundle --dart-define=AI_PROXY_URL=https://<host>/ai/chat
   # iOS: flutter build ipa --dart-define=AI_PROXY_URL=https://<host>/ai/chat
   ```
   Verilmezse uygulama çalışır ama AI yerine sezgisel özet kullanır.

> Web'de tarayıcı CORS'u OpenAI'ye doğrudan izin vermez; bu proxy CORS'u da çözer
> (sunucu `origin: true`). Yani aynı `AI_PROXY_URL` web + mobil için çalışır.

## Sonraki adımlar

- Google / Apple `id_token` doğrulama (`POST /auth/google`, `/auth/apple`).
- Firestore’dan veri migrasyon script’i.
- Flutter `ApiDataRepository` ile bu uçlara bağlanma.
