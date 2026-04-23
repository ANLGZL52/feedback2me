import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import 'api_session.dart';

/// SnackBar vb. için kısa Türkçe açıklama.
String firebaseAuthUserMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Bu giriş yöntemi şu an etkin değil. Lütfen daha sonra tekrar deneyin.';
      case 'account-exists-with-different-credential':
        return 'Bu e-posta başka bir giriş yöntemiyle kayıtlı. Önce o yöntemle giriş yapın.';
      case 'invalid-credential':
      case 'user-disabled':
        return 'Oturum açılamadı. Hesabınız veya sağlayıcı ayarları kontrol edin.';
      case 'popup-closed-by-user':
      case 'web-context-cancelled':
      case 'aborted':
        return 'Giriş penceresi kapatıldı.';
      case 'network-request-failed':
        return 'İnternet bağlantısı kurulamadı. Bağlantınızı kontrol edip tekrar deneyin.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Lütfen biraz bekleyip tekrar deneyin.';
      case 'user-not-found':
        return 'Bu hesap bulunamadı.';
      case 'credential-already-in-use':
        return 'Bu kimlik bilgisi başka bir hesaba bağlı.';
      default:
        break;
    }
    final m = error.message;
    if (m != null && m.isNotEmpty) return m;
    return error.code;
  }
  if (error is PlatformException) {
    if (error.code == 'ERROR_CANCELED' ||
        error.code == 'AuthorizationErrorCanceled' ||
        error.message?.contains('canceled') == true ||
        error.message?.contains('cancelled') == true) {
      return 'Giriş iptal edildi.';
    }
    return error.message ?? error.code;
  }
  final msg = error.toString();
  if (msg.contains('cancel') || msg.contains('Cancel')) {
    return 'Giriş iptal edildi.';
  }
  return msg;
}

/// Giriş tamamen Apple ve Google üzerinden; ödeme App Store / Google Play'da kalacak.
class AuthService {
  AuthService() {
    _auth.authStateChanges().listen((User? user) {});
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn? _googleSignIn = kIsWeb ? null : GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
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

  Future<User?> signInWithApple() async {
    try {
      final apple = AppleAuthProvider();
      apple.addScope('email');
      apple.addScope('name');
      if (kIsWeb) {
        final credential = await _auth.signInWithPopup(apple);
        return credential.user;
      }
      final credential = await _auth.signInWithProvider(apple);
      return credential.user;
    } on FirebaseAuthException catch (_) {
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'ERROR_CANCELED' ||
          e.code == 'AuthorizationErrorCanceled' ||
          (e.message?.contains('canceled') ?? false) ||
          (e.message?.contains('cancelled') ?? false)) {
        return null;
      }
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('cancel')) return null;
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) await _googleSignIn!.signOut();
    await ApiSession.instance.clear();
    await _auth.signOut();
  }
}
