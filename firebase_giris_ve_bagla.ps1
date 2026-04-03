# Node ve Firebase PATH (Cursor terminalinde kopyala-yapistir calistir)
$env:Path = "C:\Program Files\nodejs;C:\Users\CAGKAN CETINAR\AppData\Roaming\npm;" + $env:Path

# 1) Firebase'e giris - tarayici acilacak, Google ile gir
Write-Host "1. Firebase giris - tarayici acilacak..." -ForegroundColor Yellow
firebase login

# 2) Projeyi Flutter'a bagla - listeden projeni sec (feedbacktome vb.)
Write-Host "`n2. Flutter projesini Firebase'e bagla..." -ForegroundColor Yellow
Set-Location $PSScriptRoot
dart pub global run flutterfire_cli:flutterfire configure

Write-Host "`nBitti. firebase_options.dart guncellendi." -ForegroundColor Green
