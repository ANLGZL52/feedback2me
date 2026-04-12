# FeedbackToMe — Flutter'ı Railway API ile çalıştır (Firestore link/havuz/analiz yerine Postgres).
#
# Bu modda Profil'deki analiz geçmişi Firestore kurallarına BAGIMLI DEGIL; sunucu JWT + Postgres kullanir.
#
# A) En pratik: proje kokunde railway.env.json (kopyala: railway.env.example.json -> railway.env.json, gizli doldur)
#    .\run_with_railway.ps1
#
# B) Ortam degiskeni:
#   $env:FTM_DEV_AUTH_SECRET = "Railway Variables -> DEV_AUTH_SECRET ile ayni"
#   .\run_with_railway.ps1
#
# C) Parametre:
#   .\run_with_railway.ps1 -DevAuthSecret "gizli" -Device edge
#
# Android emülator / cihaz: -Device android (USB veya acik emulator)

param(
  [string] $DevAuthSecret = $env:FTM_DEV_AUTH_SECRET,
  [string] $ApiBaseUrl = "https://feedback2me-production.up.railway.app",
  [ValidateSet("chrome", "windows", "edge", "android")]
  [string] $Device = "chrome"
)

Set-Location $PSScriptRoot
$envFile = Join-Path $PSScriptRoot "railway.env.json"

if (Test-Path $envFile) {
  Write-Host "Mod: Railway (railway.env.json)" -ForegroundColor Green
  Write-Host "Cihaz: $Device`n" -ForegroundColor Green
  flutter run -d $Device --dart-define-from-file=$envFile
  exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($DevAuthSecret)) {
  Write-Host "railway.env.json yok veya DEV_AUTH_SECRET tanimli degil." -ForegroundColor Yellow
  Write-Host "  1) railway.env.example.json dosyasini railway.env.json yapip doldur, VEYA" -ForegroundColor Cyan
  Write-Host '  2) $env:FTM_DEV_AUTH_SECRET = "Railway''deki deger"' -ForegroundColor Cyan
  Write-Host "  3) .\run_with_railway.ps1`n" -ForegroundColor Cyan
  exit 1
}

Write-Host "Mod: Railway (dart-define)" -ForegroundColor Green
Write-Host "API: $ApiBaseUrl" -ForegroundColor Green
Write-Host "Cihaz: $Device`n" -ForegroundColor Green

flutter run -d $Device `
  --dart-define=USE_RAILWAY_API=true `
  --dart-define=API_BASE_URL=$ApiBaseUrl `
  --dart-define=DEV_AUTH_SECRET=$DevAuthSecret
