import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

  Future<User?> signInWithApple() async {
    try {
      if (!kIsWeb) {
        final appleProvider = AppleAuthProvider();
        final credential = await _auth.signInWithProvider(appleProvider);
        return credential.user;
      }
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCred = await _auth.signInWithCredential(oauthCredential);
      return userCred.user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) await _googleSignIn!.signOut();
    await _auth.signOut();
  }
}
