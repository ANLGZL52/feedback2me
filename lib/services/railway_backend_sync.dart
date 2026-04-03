import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../config/backend_config.dart';
import 'api_session.dart';
import 'package:http/http.dart' as http;

/// Firebase ile girişten sonra Railway dev-login ile JWT üretir (geçici köprü).
///
/// Dönüş: Railway kullanılmıyorsa `true`. Kullanılıyorsa oturum gerçekten
/// açıldıysa `true`, aksi halde `false` (çağıran SnackBar gösterebilir).
Future<bool> ensureRailwayBackendSession(User user) async {
  if (!BackendConfig.isRailwayBackendConfigured) return true;
  final secret = BackendConfig.devAuthSecret;
  if (secret.isEmpty) {
    debugPrint(
      'Railway: DEV_AUTH_SECRET tanımlı değil; dart-define ile verin.',
    );
    return false;
  }

  final base = BackendConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  final email = user.email;
  if (email == null || email.isEmpty) {
    debugPrint(
      'Railway: kullanıcı e-postası yok; dev login atlanıyor (Apple gizli e-posta?).',
    );
    return false;
  }

  final uri = Uri.parse('$base/auth/dev/login');
  try {
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Dev-Secret': secret,
      },
      body: jsonEncode({
        'email': email,
        'displayName': user.displayName,
      }),
    );
    if (res.statusCode != 200) {
      debugPrint(
        'Railway dev login başarısız: ${res.statusCode} ${res.body}',
      );
      return false;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['accessToken'] as String?;
    final userMap = data['user'] as Map<String, dynamic>?;
    final backendUid = userMap?['uid'] as String?;
    if (token != null &&
        token.isNotEmpty &&
        backendUid != null &&
        backendUid.isNotEmpty) {
      await ApiSession.instance.setSession(
        accessToken: token,
        backendUserId: backendUid,
      );
      return true;
    }
    return false;
  } catch (e, st) {
    debugPrint('Railway dev login hata: $e\n$st');
    return false;
  }
}
