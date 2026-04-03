# Firebase’i bağlamak – adım adım

1. **Firebase Console**  
   https://console.firebase.google.com/ → **Proje ekle** → İsim ver (örn. feedbacktome) → Google Analytics isteğe bağlı.

2. **Authentication**  
   Sol menü **Build** → **Authentication** → **Başlayın** → **Sign-in method** sekmesi:
   - **Google** → Etkinleştir → Kaydet.
   - **Apple** → Etkinleştir → Kaydet (Apple Developer hesabı gerekir).

3. **Firestore**  
   Sol menü **Build** → **Firestore Database** → **Veritabanı oluştur** → **Test modunda başlat** (geliştirme için) → Bölge seç (europe-west1 önerilir).

4. **Flutter tarafı**  
   Bilgisayarında Node.js yüklüyse:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
   Proje klasöründe:
   ```bash
   flutterfire configure
   ```
   Açılan listeden Firebase projeni seç, Web + Android + iOS işaretle. Bu komut `lib/firebase_options.dart` dosyasını gerçek anahtarlarla günceller.

5. **Index (link listesi için)**  
   Uygulamada “Linklerim” açıldığında Firestore index hatası çıkarsa, konsoldaki linke tıkla veya Firebase Console → Firestore → **Indexes** → **Composite** → `links` koleksiyonu, `ownerId` (Ascending) + `createdAt` (Descending) ekle.

Bu adımlardan sonra uygulamada Google/Apple ile giriş ve link/feedback kaydı çalışır.
