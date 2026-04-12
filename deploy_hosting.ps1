# Feedback form (f.html) ve web_static klasorunu Firebase Hosting'e yukler.
#
# --- Once Node.js kur (npm yok hatasi aliyorsan) ---
# Yol A: https://nodejs.org  -> "LTS" indir -> kurulumda "Add to PATH" isaretli olsun.
#        Kurulumdan sonra PowerShell'i KAPATIP yeniden ac.
# Yol B (Windows):  winget install OpenJS.NodeJS
# Kontrol:  node -v   ve   npm -v   (surum yazmalı)
#
# --- Sonra ---
#   npm.cmd install -g firebase-tools
#   firebase.cmd login
#   Bu scripti calistir.
#
# PowerShell "running scripts is disabled" derse: firebase yerine firebase.cmd kullan
#   firebase.cmd deploy --only hosting
#
# PATH'te npm yok ama Node kuruluysa (ornek):
#   $env:Path = "C:\Program Files\nodejs;" + $env:Path
#   $env:Path = "$env:APPDATA\npm;" + $env:Path

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "Hosting kaynagi: $PSScriptRoot\web_static" -ForegroundColor Cyan
if (-not (Test-Path "web_static\f.html")) {
  Write-Host "HATA: web_static\f.html bulunamadi." -ForegroundColor Red
  exit 1
}

# firebase.ps1 ExecutionPolicy'de bloklanir; firebase.cmd kullan (Windows)
$firebaseCmd = Get-Command firebase.cmd -ErrorAction SilentlyContinue
if (-not $firebaseCmd) {
  $fallback = Join-Path $env:APPDATA "npm\firebase.cmd"
  if (Test-Path $fallback) {
    $firebaseCmd = @{ Source = $fallback }
  }
}
if (-not $firebaseCmd) {
  Write-Host "firebase.cmd bulunamadi. Calistir:" -ForegroundColor Yellow
  Write-Host "  npm.cmd install -g firebase-tools" -ForegroundColor Gray
  Write-Host "  firebase.cmd login" -ForegroundColor Gray
  exit 1
}

Write-Host "`nDeploy: firebase.cmd deploy --only hosting ..." -ForegroundColor Green
& $firebaseCmd.Source deploy --only hosting
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nBitti. Tarayicida Ctrl+Shift+R (sert yenile) veya gizli pencerede ac." -ForegroundColor Green
Write-Host "URL ornek: https://feedbacktome-79655.web.app/f/SENIN_KODUN" -ForegroundColor Cyan
