@echo off
REM PowerShell ExecutionPolicy npm.ps1 engelliyorsa bu dosyayi cmd'den calistir.
cd /d "%~dp0"
set "PATH=C:\Program Files\nodejs;%PATH%"
where node >nul 2>&1 || (
  echo Node bulunamadi. Node.js kurulu mu ve PATH'te mi kontrol edin.
  pause
  exit /b 1
)
echo Firebase CLI (npx) ile giris. Tarayici acilacak.
npx --yes firebase-tools@latest login
pause
