import 'dart:js_util' as js_util;

/// Flutter Web’de Future/JS hataları bazen birkaç `.error` ile iç içe gelir.
Object? unwrapWebFutureError(Object error) {
  try {
    Object current = error;
    for (var i = 0; i < 5; i++) {
      final next = js_util.getProperty<Object?>(current, 'error');
      if (next == null) break;
      current = next;
    }
    return identical(current, error) ? null : current;
  } catch (_) {}
  return null;
}
