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

  /// Android için aynı proje; Firebase Console'da Android uygulaması eklenirse appId burada güncellenir.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M',
    appId: '1:16565078393:web:552d6701140bbca3e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
  );

  /// iOS için aynı proje; Firebase Console'da iOS uygulaması eklenirse appId burada güncellenir.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCRflC9vEs78jUte24z4mzGU2AXtaVKV_M',
    appId: '1:16565078393:web:552d6701140bbca3e747a8',
    messagingSenderId: '16565078393',
    projectId: 'feedbacktome-79655',
    authDomain: 'feedbacktome-79655.firebaseapp.com',
    storageBucket: 'feedbacktome-79655.firebasestorage.app',
  );
}
