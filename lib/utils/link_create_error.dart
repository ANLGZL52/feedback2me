import 'link_create_error_io.dart'
    if (dart.library.html) 'link_create_error_web.dart' as impl;

/// Link oluşturma SnackBar / log için okunur hata metni (web’de JS Firestore hataları dahil).
String linkCreateErrorText(Object error) => impl.linkCreateErrorTextImpl(error);
