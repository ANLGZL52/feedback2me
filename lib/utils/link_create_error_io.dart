import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import 'unwrap_web_future_error.dart';

/// Mobil / masaüstü: Firestore ve auth hataları için okunur metin.
String linkCreateErrorTextImpl(Object error) {
  Object e = unwrapWebFutureError(error) ?? error;
  e = unwrapWebFutureError(e) ?? e;
  return _format(e);
}

String _format(Object e) {
  if (e is FirebaseException) {
    final m = e.message;
    if (m != null && m.isNotEmpty) return '${e.code}: $m';
    return e.code;
  }
  if (e is StateError) return e.message;
  try {
    final d = e as dynamic;
    final msg = d.message;
    final code = d.code;
    if (msg is String && msg.isNotEmpty) {
      final c = code is String && code.isNotEmpty ? code : 'error';
      return '$c: $msg';
    }
    if (code is String && code.isNotEmpty) return code;
  } catch (_) {}
  final t = e.toString();
  if (t == '[object Object]' || t == '[object Error]') {
    return 'bilinmeyen_firestore_hatasi — ayrıntı için cihaz loglarına bakın';
  }
  return t;
}
