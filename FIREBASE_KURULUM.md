# Firebase kurulumu – FeedbackToMe

Aşağıdaki adımları sırayla yap. Ücretsiz Spark planı yeterli.

**Gereksinim:** Bilgisayarda **Node.js** yüklü olmalı (https://nodejs.org — LTS sürümü). Kurduktan sonra terminali yeniden aç. `node -v` ve `npm -v` yazıp sürüm görünüyorsa hazırsın.

---

## 1. Firebase projesi oluştur

1. Tarayıcıda **https://console.firebase.google.com/** aç.
2. **Proje ekle** (veya "Create a project").
3. Proje adı: **feedbacktome** (veya istediğin isim).
4. Google Analytics: İstersen **Şimdi etkinleştirme** diyebilirsin (isteğe bağlı).
5. **Proje oluştur** de.

---

## 2. Authentication (Google + Apple)

1. Sol menüden **Build** → **Authentication**.
2. **Başlayın** / **Get started**.
3. **Sign-in method** sekmesine geç.
4. **Google** satırına tıkla → **Etkinleştir** → **Kaydet**.
5. **Apple** satırına tıkla → **Etkinleştir** → Kaydet.  
   (Apple için Apple Developer hesabı gerekir; şimdilik atlayıp sadece Google ile de devam edebilirsin.)

---

## 3. Firestore veritabanı

1. Sol menüden **Build** → **Firestore Database**.
2. **Veritabanı oluştur**.
3. **Test modunda başlat** seç (geliştirme için; kuralları sonra güncellersin).
4. Konum: **europe-west1** (veya en yakın bölge) → **Etkinleştir**.

---

## 4. Flutter tarafı – `flutterfire configure`

Bilgisayarında **Node.js** yüklü olmalı (https://nodejs.org). Sonra:

### 4.1 Firebase CLI (bir kez)

Terminalde:

```bash
npm install -g firebase-tools
firebase login
```

Tarayıcı açılır; Google hesabınla giriş yap.

### 4.2 FlutterFire CLI (bir kez)

```bash
dart pub global activate flutterfire_cli
```

### 4.3 Projeyi Firebase’e bağla

Proje klasörüne geç (içinde `pubspec.yaml` olan klasör):

```bash
cd "c:\Users\CAGKAN CETINAR\Desktop\FEEDBACKTOME\feedback_to_me"
dart run flutterfire_cli:flutterfire configure
```

(PATH’e eklemediysen `flutterfire` yerine `dart run flutterfire_cli:flutterfire` kullan. PATH’e eklediysen sadece `flutterfire configure` yazabilirsin.)

- Açılan listeden **feedbacktome** (veya oluşturduğun proje adı) projesini seç.
- Platformlar: **Web**, **Android**, **iOS** işaretli olsun.
- Enter’a bas; `lib/firebase_options.dart` dosyası gerçek anahtarlarla oluşturulur.

---

## 5. Web’de Google ile giriş (Chrome’da denemek için)

Web’de Google girişi çalışsın diye:

1. Firebase Console → **Project settings** (dişli) → **General**.
2. Aşağıda **Your apps** → **Web** uygulaması (</> simgesi). Yoksa **Add app** → **Web** ile ekle.
3. **SDK setup and configuration** içinde **Config** objesinde `clientId` veya OAuth 2.0 Client ID’yi bul (veya Authentication → Sign-in method → Google → **Web client ID**).
4. Projede `web/index.html` dosyasını aç; şu satırı bul:

```html
<meta name="google-signin-client_id" content="PLACEHOLDER_WEB.apps.googleusercontent.com">
```

5. `content="..."` içini Firebase’teki **Web client ID** ile değiştir (örn. `123456789-xxx.apps.googleusercontent.com`).
6. `lib/services/auth_service.dart` içinde web için kullanılan `clientId` de aynı değer olmalı. Şu an placeholder var; `firebase_options` ile doldurabilirsin veya `index.html`’deki meta tag yeterli olabilir (Google Sign-In bazen oradan okur).

---

## 6. Firestore index (gerekirse)

Uygulamada “Linklerim” veya rapor açılırken **index** hatası çıkarsa:

- Hata mesajındaki linke tıkla (otomatik index oluşturur),  
  **veya**
- Firebase Console → **Firestore** → **Indexes** → **Composite** → `links` için `ownerId` (Ascending) + `createdAt` (Descending) ekle.

---

## Özet kontrol

- [ ] Firebase projesi oluşturuldu  
- [ ] Authentication’da Google (ve istenirse Apple) açıldı  
- [ ] Firestore test modunda oluşturuldu  
- [ ] `firebase login` yapıldı  
- [ ] `flutterfire configure` çalıştırıldı, `lib/firebase_options.dart` güncel  
- [ ] Web kullanacaksan `web/index.html` içinde `google-signin-client_id` güncellendi  

Bunlardan sonra uygulamada Google (ve Apple) ile giriş ve link/feedback kaydı çalışır.
