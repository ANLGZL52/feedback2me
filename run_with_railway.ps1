# FeedbackToMe — Flutter'ı Railway API ile çalıştır (Chrome)
#
# Kullanım (önerilen):
#   $env:FTM_DEV_AUTH_SECRET = "Railway Variables → DEV_AUTH_SECRET ile aynı"
#   .\run_with_railway.ps1
#
# İsteğe bağlı:
#   .\run_with_railway.ps1 -DevAuthSecret "gizli-deger"
#   .\run_with_railway.ps1 -Device windows   # Visual Studio C++ gerekir

param(
  [string] $DevAuthSecret = $env:FTM_DEV_AUTH_SECRET,
  [string] $ApiBaseUrl = "https://feedback2me-production.up.railway.app",
  [ValidateSet("chrome", "windows", "edge")]
  [string] $Device = "chrome"
)

if ([string]::IsNullOrWhiteSpace($DevAuthSecret)) {
  Write-Host "DEV_AUTH_SECRET gerekli. Örnek:" -ForegroundColor Yellow
  Write-Host '  $env:FTM_DEV_AUTH_SECRET = "Railway''deki deger"' -ForegroundColor Cyan
  Write-Host "  .\run_with_railway.ps1`n" -ForegroundColor Yellow
  exit 1
}

Write-Host "API: $ApiBaseUrl" -ForegroundColor Green
Write-Host "Cihaz: $Device`n" -ForegroundColor Green

flutter run -d $Device `
  --dart-define=USE_RAILWAY_API=true `
  --dart-define=API_BASE_URL=$ApiBaseUrl `
  --dart-define=DEV_AUTH_SECRET=$DevAuthSecret
