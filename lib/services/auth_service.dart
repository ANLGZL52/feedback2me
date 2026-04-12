import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'api_session.dart';

/// SnackBar vb. için kısa Türkçe açıklama.
String firebaseAuthUserMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Firebase’de bu giriş yöntemi kapalı. Firebase Console → '
            'Authentication → Giriş yöntemleri → Apple’ı açıp Apple Developer '
            '(Services ID, anahtar, Team ID) bilgilerini girin.';
      case 'account-exists-with-different-credential':
        return 'Bu e-posta başka bir giriş yöntemiyle kayıtlı. Önce o yöntemle giriş yapın.';
      case 'invalid-credential':
      case 'user-disabled':
        return 'Oturum açılamadı. Hesabınız veya sağlayıcı ayarları kontrol edin.';
      case 'popup-closed-by-user':
      case 'web-context-cancelled':
      case 'aborted':
        return 'Giriş penceresi kapatıldı.';
      default:
        break;
    }
    final m = error.message;
    if (m != null && m.isNotEmpty) return m;
    return error.code;
  }
  return error.toString();
}

/// Giriş tamamen Apple ve Google üzerinden; ödeme App Store / Google Play'da kalacak.
class AuthService {
  AuthService() {
    _auth.authStateChanges().listen((User? user) {});
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  /// Mobilde GoogleSignIn; web'de signInWithPopup (client ID gerekmez)
  final GoogleSignIn? _googleSignIn = kIsWeb ? null : GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web: signInWithPopup Firebase config kullanır, ayrı client ID gerekmez
        final credential = await _auth.signInWithPopup(GoogleAuthProvider());
        return credential.user;
      }
      final googleUser = await _googleSignIn!.signIn();
      if (googleUser == null) return null;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      return userCred.user;
    } catch (e) {
      rethrow;
    }
  }

  /// Web: [signInWithPopup] (Google ile aynı model; `sign_in_with_apple` web JS interop hatası veriyordu).
  /// iOS/Android: [signInWithProvider].
  Future<User?> signInWithApple() async {
    try {
      final apple = AppleAuthProvider();
      if (kIsWeb) {
        final credential = await _auth.signInWithPopup(apple);
        return credential.user;
      }
      final credential = await _auth.signInWithProvider(apple);
      return credential.user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) await _googleSignIn!.signOut();
    await ApiSession.instance.clear();
    await _auth.signOut();
  }
}
