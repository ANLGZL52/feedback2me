import 'unwrap_web_future_error_stub.dart'
    if (dart.library.html) 'unwrap_web_future_error_web.dart' as impl;

Object? unwrapWebFutureError(Object error) => impl.unwrapWebFutureError(error);
