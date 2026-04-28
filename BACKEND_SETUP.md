# FeedbackToMe – Backend ve giriş kurulumu

## 1. Firebase projesi

1. [Firebase Console](https://console.firebase.google.com/) → Yeni proje oluştur.
2. Projede **Authentication** aç; **Google** ve **Apple** oturum açma yöntemlerini etkinleştir.
3. **Firestore Database** oluştur (test modunda başlayabilirsin).
4. **Firestore indexes**: `firestore.indexes.json` dosyası proje kökünde. Index’i Firebase Console → Firestore → Indexes üzerinden ekleyebilir veya `firebase deploy --only firestore:indexes` ile dağıtabilirsin.

## 2. Flutter tarafında Firebase yapılandırması

Terminalde proje klasöründe:

```bash
# Firebase CLI yüklü olmalı: npm install -g firebase-tools
# Ardından:
flutterfire configure
```

Bu komut:

- Firebase projeni seçmeni ister.
- Web / Android / iOS için uygulama ekler.
- `lib/firebase_options.dart` dosyasını **gerçek** API anahtarlarıyla oluşturur.

`firebase_options.dart` gerçek değerlerle dolu. Web’de Google girişi `signInWithPopup` ile yapılıyor (ek client ID gerekmez). Mobil için `flutterfire configure` ile proje/uygulama eşleştirilir.

## 3. Ödeme — link başına (tüketilebilir IAP)

Model: **Tek seferlik link kredisi** (`premium_link_single`, consumable). Her satın alma hesaba +1 kredi yazar; bir premium link oluşturulunca kredi düşer. Aylık/yinelenen ücret yok.

- **Apple:** App Store Connect → In-App Purchases → **Consumable**, ürün kimliği `premium_link_single`. Ürünü oluşturduktan sonra **yeni uygulama sürümünde** bu IAP’yi inceleme paketine **mutlaka ekleyin** (yalnızca binary göndermek Guideline 2.1(b) reddine yol açabilir). Ayrıntılar: `lib/config/iap_products.dart` üst yorumları.
- **Google:** Play Console → One-time products → aynı ürün kimliği.
- **Flutter:** `in_app_purchase`; teslimatta Firestore `paidLinkCredits` güncellenir. İsteğe bağlı eski alanlar: `isPremium` / `premiumUntil` (geriye dönük).

Ödeme yalnızca App Store / Google Play üzerinden.

## 4. Koleksiyonlar (Firestore)

- **users** – `uid` = Firebase Auth UID. Alanlar: `displayName`, `email`, `photoUrl`, `handle`, `isPremium`, `premiumUntil`, `createdAt`.
- **links** – Her doküman bir feedback linki. Alanlar: `ownerId`, `code` (8 karakter), `title`, `createdAt`, `isActive`.
- **feedbacks** – Her doküman bir yorum. Alanlar: `linkId`, `responderName`, `relation`, `mood`, `textRaw`, `textClean` (ileride AI), `createdAt`.

Raporlama ve analiz: Gelen yorum sayısına göre raporun kapsamı ve detayı artacak şekilde tasarlanmalı (az yorum → kısa özet, çok yorum → daha uzun, tema bazlı, yüzdeli ve madde madde detaylı rapor). İleride Cloud Functions veya başka bir backend’de toplu işlem ve AI entegrasyonu eklenebilir.

## 5. Railway API (Firestore analiz / havuz / link senkronu istemiyorsan)

Uygulama varsayılanında `USE_RAILWAY_API=false` olduğu için **linkler, yorum havuzu ve takipçi analiz geçmişi Firestore** üzerinden gider; `audienceScoreSnapshots` için güvenlik kuralları şarttır.

**Railway modunda** (`USE_RAILWAY_API=true` + `API_BASE_URL` + giriş sonrası sunucu oturumu) veri **Postgres + REST API** ile gider; Profil’deki analiz listesi Firestore’a hiç dokunmaz, `permission-denied` bu yüzden ortadan kalkar (giriş ve Railway ortam değişkenleri doğruysa).

Yerelde çalıştırma:

1. `railway.env.example.json` dosyasını `railway.env.json` olarak kopyala (bu dosya `.gitignore`’da; gizli anahtarı repoya koyma).
2. `DEV_AUTH_SECRET` değerini Railway’deki `DEV_AUTH_SECRET` ile aynı yap; `API_BASE_URL`’i kendi Railway URL’in ile güncelle.
3. `.\run_with_railway.ps1` — varsa `railway.env.json` ile `flutter run` çalışır; Android için `-Device android`.

Üretim APK / web build için aynı tanımları derleme sırasında ver:

```bash
flutter build apk --dart-define-from-file=railway.env.json
# veya
flutter build web --dart-define-from-file=railway.env.json
```

Sunucuda `ALLOW_DEV_AUTH=true` ve aynı `DEV_AUTH_SECRET` olmalı; ayrıntılar `server/README.md`.
