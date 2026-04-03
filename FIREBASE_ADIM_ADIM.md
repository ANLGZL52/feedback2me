# Firebase – Adım adım (Chrome’da bulamıyorsan)

## A) Node.js kur (bir kez)

1. Şu linke git: **https://nodejs.org**
2. Yeşil **"LTS"** butonuna tıkla (Recommended).
3. İnen dosyayı çalıştır, **Next** ile kurulumu bitir.
4. **Bilgisayarı yeniden başlat** veya Cursor’u kapatıp aç.
5. Sonra B ve C’ye geç.

---

## B) Firebase Console’da (Chrome’daki sekme)

Console açıkken:

### 1. Proje

- Üstte veya solda **proje adı** görünüyor mu? (Örn. "feedbacktome")
- **Yoksa:** Sol üstte **"Proje ekle"** / **"Add project"** → İsim ver → Oluştur.

### 2. Authentication (Giriş)

- **Sol menü:** En soldaki çubukta aşağı kaydır.
- **"Build"** (veya **Oluştur**) bölümünü bul (bazen ikon: 🔨 veya kutular).
- Altında **"Authentication"** yazısına tıkla.
- **"Get started"** / **"Başlayın"** butonuna bas.
- Üstte **"Sign-in method"** sekmesine geç.
- Listede **"Google"** satırına tıkla → **"Enable"** / **"Etkinleştir"** → **Save** / **Kaydet**.

### 3. Firestore (Veritabanı)

- Yine sol menüde **"Build"** altında **"Firestore Database"** yazısına tıkla.
- **"Create database"** / **"Veritabanı oluştur"**.
- **"Start in test mode"** / **"Test modunda başlat"** seç → **Next**.
- Konum: **europe-west1** (veya varsayılan) → **Enable** / **Etkinleştir**.

Bittiğinde C’ye geç.

---

## C) Bilgisayarda terminal (Cursor içinde)

Node.js kurduktan ve Cursor’u yeniden açtıktan sonra:

1. **Firebase CLI kur + giriş:**

```
npm install -g firebase-tools
firebase login
```

Tarayıcı açılır; Google hesabınla giriş yap.

2. **Projeyi Flutter’a bağla:**

```
cd "c:\Users\CAGKAN CETINAR\Desktop\FEEDBACKTOME\feedback_to_me"
flutterfire configure
```

(veya: `dart pub global run flutterfire_cli:flutterfire configure`)

- Açılan listeden **feedbacktome** (veya kendi proje adın) projesini seç.
- **Web, Android, iOS** işaretli kalsın → Enter.

Bu işlem `lib/firebase_options.dart` dosyasını günceller. Sonra uygulamada Google ile giriş deneyebilirsin.

---

## D) Web’de Google girişi (Chrome’da uygulamayı deneyeceksen)

- Firebase Console → Sol altta **dişli** (⚙️) **Project settings**.
- Aşağıda **"Your apps"** → Web uygulaması (</>). Yoksa **"Add app"** → **Web**.
- **"Web client ID"** veya config’teki **client ID**’yi kopyala.
- Projede **`web/index.html`** aç; şu satırı bul ve `content="..."` içine bu ID’yi yapıştır:

```html
<meta name="google-signin-client_id" content="BURAYA_YAPIŞTIR">
```
