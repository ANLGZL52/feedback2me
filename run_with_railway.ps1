# FeedbackToMe — Railway API ile Flutter
# DEV_AUTH_SECRET: Railway Variables ile birebir aynı olmalı.

$DevAuthSecret = "RAILWAY_DEV_AUTH_SECRET_ILE_AYNI"
$ApiBaseUrl = "https://feedback2me-production.up.railway.app"

# Windows masaustu icin: flutter run -d windows (Visual Studio C++ workload gerekir)
# Web: -d chrome
flutter run -d chrome `
  --dart-define=USE_RAILWAY_API=true `
  --dart-define=API_BASE_URL=$ApiBaseUrl `
  --dart-define=DEV_AUTH_SECRET=$DevAuthSecret
