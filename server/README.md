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

## Railway

1. Yeni servis → **GitHub repo** → root directory: **`server`** (veya monorepo kökünde Dockerfile path ayarla).
2. **PostgreSQL** ekle; `DATABASE_URL` API servisine bağlanır (Reference variables).
3. **Variables:** `JWT_SECRET`, isteğe bağlı `ALLOW_DEV_AUTH` / `DEV_AUTH_SECRET` (sadece test).
4. **Build:** `npm ci && npm run build` veya Dockerfile kullan.
5. **Start:** `node dist/index.js` — `PORT` Railway tarafından verilir.

## Sonraki adımlar

- Google / Apple `id_token` doğrulama (`POST /auth/google`, `/auth/apple`).
- Firestore’dan veri migrasyon script’i.
- Flutter `ApiDataRepository` ile bu uçlara bağlanma.
