# FeedbackToMe Web — Kayıt (Devam için)

**Tarih:** 4 Mart 2026  
**Durum:** Statik sayfa yayında. Flutter web sürümü şimdilik bir kenara bırakıldı (Chrome’da yükleme ekranında takılıyor, kök sebep bulunamadı).

---

## Şu an yayında olan

- **Adres:** https://feedbacktome-79655.web.app
- **İçerik:** Statik HTML sayfa (`web_static/index.html`)
  - Koyu tema, FeedbackToMe logosu
  - "Web sürümü güncelleniyor. Mobil uygulamayı mağazalardan indirebilirsiniz" metni
- **Firebase Hosting:** `firebase.json` içinde `"public": "web_static"` (Flutter build değil)

---

## Daha sonra Flutter web’e dönmek için

1. `firebase.json` içinde şunu değiştir:
   - `"public": "web_static"` → `"public": "build/web"`
2. PowerShell’de:
   ```powershell
   cd "c:\Users\CAGKAN CETINAR\Desktop\FEEDBACKTOME\feedback_to_me"
   flutter build web
   firebase deploy
   ```
3. Flutter web’de yaşanan sorun (yükleme takılması, gri ekran) nedeniyle Flutter web şimdilik bir kenara bırakıldı; bu dosyayı açıp “Flutter web’i düzeltmek istiyorum” diyerek devam edebilirsin.

---

## Projede yapılanlar (özet)

- Firebase config: `lib/firebase_options.dart` ve `web/index.html` (Firebase JS SDK + init)
- Firebase Hosting: `firebase.json`, `.firebaserc` (proje: feedbacktome-79655)
- Flutter web: `main.dart` içinde web için `_WebSplash` (2 sn timeout), `_AuthGate`, `_WebInitWrapper`; LandingScreen layout düzeltmeleri
- Statik sayfa: `web_static/index.html` — şu an bu yayında
- Rehber: `NASIL_YUKLEYECEGIM.md` (PowerShell, firebase login, deploy adımları)

---

## Daha sonra devam ederken

- Bu dosyayı aç: `WEB_DURUM_DEVAM.md`
- “Web’de Flutter uygulamasını açmak istiyorum” veya “Statik sayfayı güncellemek istiyorum” gibi ne yapmak istediğini yaz; oradan devam ederiz.
