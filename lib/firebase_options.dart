// Firebase yapılandırması — Feedback2Me projesi (feedbacktome-79655)
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

  /// Android: Google ile giriş için Firebase Console’da **Android uygulaması** ekleyip
  /// gerçek `appId` (mobilesdk) buraya yazın; paket adı `app.feedbacktome` ile eşleşmeli.
  /// Ayrıca Play Integrity / SHA-1 (veya SHA-256) sertifikalarını Console’a ekleyin.
  /// İsterseniz: `dart pub global activate flutterfire_cli` → `flutterfire configure`
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M',
    appId: '1:16565078393:android:14cb32626446e212e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
  );

  /// iOS: bundle id `com.anlgzl.feedback2meapp` için Firebase uygulaması.
  /// `apiKey`, `ios/Runner/GoogleService-Info.plist` içindeki `API_KEY` ile aynı olmalı.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAIU91FpUp7C9NW0sn0F8DiaQ5pztjv5Lc',
    appId: '1:16565078393:ios:c9577651fba3a805e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
  );
}
