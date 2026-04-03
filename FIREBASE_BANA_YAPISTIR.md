# Firebase değerlerini bana yapıştır

Aşağıdaki adımları yap, çıkan değerleri **bu sohbet penceresine** kopyala-yapıştır. Ben senin yerine `firebase_options.dart` dosyasını dolduracağım.

---

## 1. Firebase Console’u aç

Chrome’da: **https://console.firebase.google.com/**

(Projeni seç – örn. feedbacktome)

---

## 2. Proje ayarlarına gir

- Sol altta **dişli (⚙️)** simgesine tıkla  
- **"Project settings"** / **"Proje ayarları"** seç

---

## 3. “Your apps” / “Uygulamalarım” bölümü

Aşağı kaydır, **"Your apps"** bölümüne gel.

### Web uygulaması yoksa

- **"</> Web"** veya **"Add app" → "Web"** tıkla  
- Uygulama adı (örn. feedback-to-me-web) yaz → **Register app**  
- Bir sonraki ekranda **firebaseConfig** içindeki değerler görünür (apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId). Bunları kopyala.

### Web uygulaması varsa

- **</> Web** kartına tıkla  
- **"SDK setup and configuration"** / **"Config"** bölümünde şuna benzer bir blok görürsün:

```javascript
const firebaseConfig = {
  apiKey: "AIza...",
  authDomain: "xxx.firebaseapp.com",
  projectId: "xxx",
  storageBucket: "xxx.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abc..."
};
```

**Bu 6 satırın tamamını** (apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId) kopyala.

---

## 4. Android uygulaması

Aynı **Project settings** sayfasında:

- **Android** (Android robotu) ikonuna tıkla veya **"Add app" → "Android"**
- **Android package name** kutusuna şunu yaz: **com.example.feedback_to_me**
- **Register app** de
- Sonraki ekranda yine **config** (apiKey, projectId, appId vb.) görünür. **Android için appId** genelde **1:xxx:android:yyy** şeklindedir. Bu **appId** değerini de kopyala (ve mümkünse tüm Android config’i).

---

## 5. Bana yapıştır

Bu sohbet penceresine (Cursor chat’e) şunu yaz:

**Web config:**  
(apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId – hepsini yapıştır)

**Android appId:**  
(Android uygulaması eklediysen, Android’e ait appId)

Örnek:
```
projectId: feedbacktome-xxx
apiKey: AIzaSy...
authDomain: feedbacktome-xxx.firebaseapp.com
storageBucket: feedbacktome-xxx.appspot.com
messagingSenderId: 123456789
web appId: 1:123456789:web:abc123
android appId: 1:123456789:android:def456
```

Bu 6–7 satırı bana yapıştırman yeterli; ben `firebase_options.dart` dosyasını senin için yazacağım.
