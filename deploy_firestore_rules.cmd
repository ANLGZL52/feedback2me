@echo off
REM firestore.rules dosyasini Firebase'e yukler. Once firebase_login.cmd ile giris yap.
cd /d "%~dp0"
set "PATH=C:\Program Files\nodejs;%PATH%"
where node >nul 2>&1 || (
  echo Node bulunamadi. Node.js kurulu mu ve PATH'te mi kontrol edin.
  pause
  exit /b 1
)
echo firestore.rules deploy ediliyor...
npx --yes firebase-tools@latest deploy --only firestore:rules
echo.
if errorlevel 1 (
  echo HATA: Yukaridaki mesaji okuyun. Genelde once firebase_login.cmd calistirilir.
) else (
  echo Tamam.
)
pause
