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

/// Takipçi analizi kayıtları (`audienceScoreSnapshots`): Firestore kuralları `users/{auth.uid}` ile hizalı olmalı.
/// Railway’de liste/detay API oturumdan okunur; [dataOwnerId] yalnızca imza uyumu / yedek.
String audienceRecordsOwnerKey(String firebaseAuthUid, String? dataOwnerId) {
  if (!BackendConfig.isRailwayBackendConfigured) {
    return firebaseAuthUid;
  }
  final o = dataOwnerId?.trim();
  if (o != null && o.isNotEmpty) return o;
  return firebaseAuthUid;
}
