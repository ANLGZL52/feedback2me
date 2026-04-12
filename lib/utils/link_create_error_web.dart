import 'dart:js_util' as js_util;

import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import 'unwrap_web_future_error.dart';

/// Web: Firestore JS hataları çoğu zaman [object Object] string üretir; [code]/[message] okunur.
String linkCreateErrorTextImpl(Object error) {
  Object e = unwrapWebFutureError(error) ?? error;
  e = unwrapWebFutureError(e) ?? e;

  final fromJs = _readJsFirebaseFields(e);
  if (fromJs != null) return fromJs;

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
    return 'bilinmeyen_firestore_hatasi — Tarayıcıda F12 → Console’daki kırmızı satırı kontrol et';
  }
  return t;
}

String? _readJsFirebaseFields(Object e) {
  try {
    final code = js_util.getProperty<Object?>(e, 'code');
    final message = js_util.getProperty<Object?>(e, 'message');
    final ms = _jsToString(message);
    if (ms != null && ms.isNotEmpty) {
      final cs = _jsToString(code);
      return '${cs ?? 'firebase'}: $ms';
    }
    final csOnly = _jsToString(code);
    if (csOnly != null && csOnly.isNotEmpty) return csOnly;
  } catch (_) {}
  return null;
}

String? _jsToString(Object? v) {
  if (v == null) return null;
  final s = '$v';
  if (s.isEmpty || s == 'null' || s == 'undefined') return null;
  return s;
}
