import 'package:flutter/material.dart';

import 'config/backend_config.dart';
import 'services/api_session.dart';
import 'services/app_data_backend.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/iap_service.dart';
import 'services/railway_api_service.dart';

final authService = AuthService();

final FirestoreService _firestoreBackend = FirestoreService();
final RailwayApiService _railwayBackend = RailwayApiService();

/// Firestore veya Railway — [BackendConfig] ile seçilir.
AppDataBackend get appData =>
    BackendConfig.isRailwayBackendConfigured ? _railwayBackend : _firestoreBackend;

final iapService = IapService();

/// Dil seçimi: null = cihaz dili, Locale('en') = İngilizce, Locale('tr') = Türkçe.
final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

/// Railway kullanılırken: Postgres `User.id`. Firestore modunda Firebase `uid`.
String? effectiveDataOwnerId(String? firebaseUid) {
  if (firebaseUid == null) return null;
  if (!BackendConfig.isRailwayBackendConfigured) return firebaseUid;
  return ApiSession.instance.backendUserId;
}
