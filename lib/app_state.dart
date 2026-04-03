import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/iap_service.dart';

final authService = AuthService();
final firestoreService = FirestoreService();
final iapService = IapService();

/// Dil seçimi: null = cihaz dili, Locale('en') = İngilizce, Locale('tr') = Türkçe.
final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);
