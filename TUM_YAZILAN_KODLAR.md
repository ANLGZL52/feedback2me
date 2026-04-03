# FeedbackToMe — Yazılan / Değiştirilen Kodlar

Bu dosya, projede yazılan veya değiştirilen tüm kodları içerir. Başka bir yerde soracağın için tamamı burada.

---

## 1. lib/firebase_options.dart

```dart
// Firebase yapılandırması — FeedbackToMe projesi (feedbacktome-79655)
// Web config ile oluşturuldu. Android/iOS için ileride Firebase Console'dan uygulama ekleyip appId güncellenebilir.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M',
    appId: '1:16565078393:web:552d6701140bbca3e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
    measurementId: 'G-RHFSKYCS76',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M',
    appId: '1:16565078393:web:552d6701140bbca3e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M',
    appId: '1:16565078393:web:552d6701140bbca3e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
  );
}
```

---

## 2. firebase.json

```json
{
  "hosting": {
    "public": "web_static",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ]
  }
}
```

---

## 3. .firebaserc

```json
{
  "projects": {
    "default": "feedbacktome-79655"
  }
}
```

---

## 4. web_static/index.html (Statik sayfa — şu an yayında)

```html
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
  <meta http-equiv="Pragma" content="no-cache">
  <meta http-equiv="Expires" content="0">
  <title>FeedbackToMe</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #141210;
      color: #fff;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
      text-align: center;
    }
    .logo { font-size: 1.75rem; font-weight: 700; color: #D4AF37; margin-bottom: 8px; }
    .tagline { color: rgba(255,255,255,0.85); font-size: 1rem; max-width: 360px; line-height: 1.5; margin-bottom: 32px; }
    .card {
      background: #1C1917;
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: 16px;
      padding: 24px;
      max-width: 400px;
      width: 100%;
    }
    .card h2 { font-size: 1.1rem; margin-bottom: 12px; color: #fff; }
    .card p { color: rgba(255,255,255,0.7); font-size: 0.9rem; line-height: 1.5; }
    .note { margin-top: 24px; font-size: 0.85rem; color: rgba(255,255,255,0.5); }
  </style>
</head>
<body>
  <div class="logo">FeedbackToMe</div>
  <p class="tagline">Tek linkle geri bildirim topla. AI ile rapora dönüştür.</p>
  <div class="card">
    <h2>Hoş geldiniz</h2>
    <p>Web sürümü şu an güncelleniyor. Uygulamayı kullanmak için <strong>Android</strong> veya <strong>iOS</strong> cihazınızdan mağazalardan indirebilirsiniz.</p>
  </div>
  <p class="note">feedbacktome-79655.web.app</p>
</body>
</html>
```

---

## 5. web/index.html (Firebase Flutter web için)

**Önemli eklemeler:**

- `<div id="loading-fallback">Yükleniyor...</div>` (body başında)
- Firebase JS SDK script'leri:
```html
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-auth-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-firestore-compat.js"></script>
<script>
  var firebaseConfig = {
    apiKey: "AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M",
    authDomain: "feedbacktome-79655.firebaseapp.com",
    projectId: "feedbacktome-79655",
    storageBucket: "feedbacktome-79655.firebasestorage.app",
    messagingSenderId: "16565078393",
    appId: "1:16565078393:web:552d6701140bbca3e747a8",
    measurementId: "G-RHFSKYCS76"
  };
  if (typeof firebase !== 'undefined') firebase.initializeApp(firebaseConfig);
</script>
```
- `removeSplashFromWeb()` içinde: `document.getElementById("loading-fallback")?.remove();`
- 15 sn timeout fallback script

---

## 6. lib/main.dart — Yapılan değişiklikler

### 6.1 Imports eklenenler
```dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
```

### 6.2 main() — Web branch
```dart
if (kIsWeb) {
  runApp(const _WebSplash());
  return;
}
```

### 6.3 _WebSplash widget (satır ~56-110)
```dart
class _WebSplash extends StatefulWidget {
  const _WebSplash();
  @override
  State<_WebSplash> createState() => _WebSplashState();
}

class _WebSplashState extends State<_WebSplash> {
  bool _go = false;

  void _openApp() {
    if (!mounted || _go) return;
    setState(() => _go = true);
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), _openApp);
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((_) {
          SharedPreferences.getInstance().then((prefs) {
            L10n.setPrefs(prefs);
            L10n.loadSavedLocale();
          }).catchError((_) {});
          _openApp();
        })
        .catchError((_) => _openApp());
  }

  @override
  Widget build(BuildContext context) {
    if (!_go) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141210),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFD4AF37)),
                const SizedBox(height: 24),
                Text('Yükleniyor...', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 20)),
              ],
            ),
          ),
        ),
      );
    }
    return const FeedbackToMeApp();
  }
}
```

### 6.4 _AuthGate widget (satır ~232-280)
```dart
class _AuthGate extends StatefulWidget { ... }

class _AuthGateState extends State<_AuthGate> {
  User? _user;
  bool _timedOut = false;
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = authService.authStateChanges.listen((user) {
      if (mounted) setState(() => _user = user);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_timedOut) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user != null || _timedOut) return const LandingScreen();
    return Scaffold(
      backgroundColor: const Color(0xFF141210),
      body: Center(child: Column(..., 'Yükleniyor...'), ...),
    );
  }
}
```

### 6.5 FeedbackToMeApp — MaterialApp'e eklenen
```dart
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

### 6.6 LandingScreen _buildLandingBody — Yapılan değişiklikler
- `Scaffold` içinde: `backgroundColor: const Color(0xFF141210),`
- Column'da: `Spacer()` kaldırıldı, `mainAxisSize: MainAxisSize.min` eklendi
- `const Spacer()` yerine `const SizedBox(height: 32)` eklendi

### 6.7 SnackBar const düzeltmeleri (derleme hatası için)
- `const SnackBar(content: Text(L10n.get(context, 'linkCopied')))` → `SnackBar(content: Text(L10n.get(context, 'linkCopied')))`
- `const SnackBar(content: Text(L10n.get(context, 'savedToGallery')))` → `SnackBar(...)`
- `const SnackBar(content: Text(L10n.get(context, 'imageError')))` → `SnackBar(...)`

---

## 7. _WebInitWrapper (kullanılmıyor ama kodda duruyor)

2 sn timeout ile "Yenile" ekranı gösteren alternatif wrapper. Şu an main() web için _WebSplash kullanılıyor.

---

## Özet

| Dosya | Açıklama |
|-------|----------|
| `lib/firebase_options.dart` | Firebase config (web/android/ios) |
| `firebase.json` | Hosting: web_static klasörü |
| `.firebaserc` | Proje: feedbacktome-79655 |
| `web_static/index.html` | Statik "Hoş geldiniz" sayfası (yayında) |
| `web/index.html` | Firebase SDK + init, loading-fallback |
| `lib/main.dart` | Web: _WebSplash, _AuthGate; localizationsDelegates; SnackBar/Spacer düzeltmeleri |
