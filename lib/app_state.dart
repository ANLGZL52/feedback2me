import 'package:flutter/material.dart';

import 'config/backend_config.dart';
import 'services/api_session.dart';
import 'services/app_data_backend.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/iap_service.dart';
import 'services/railway_api_service.dart';

/// [Firebase.initializeApp] sonrasında bir kez çağrılmalı; aksi halde Firebase
/// kullanıcısı oluşturulmadan [FirebaseAuth]/[FirebaseFirestore] erişimi iOS’ta
/// çökme üretebilir.
bool _appStateInitialized = false;

late final AuthService authService;

late final FirestoreService _firestoreBackend;
final RailwayApiService _railwayBackend = RailwayApiService();

/// Firestore veya Railway — [BackendConfig] ile seçilir.
AppDataBackend get appData =>
    BackendConfig.isRailwayBackendConfigured ? _railwayBackend : _firestoreBackend;

late final IapService iapService;

void initializeAppState() {
  if (_appStateInitialized) return;
  _appStateInitialized = true;
  authService = AuthService();
  _firestoreBackend = FirestoreService();
  iapService = IapService();
}

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
