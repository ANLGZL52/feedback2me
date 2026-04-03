# FeedbackToMe Web’i Firebase’e Nasıl Yüklersin?

Bu rehber, uygulamayı **https://feedbacktome-79655.web.app** adresine yayınlamak için yapman gereken iki adımı anlatıyor.

---

## Adım 1: PowerShell’i aç

1. Klavyede **Windows tuşuna** bas (space’in solunda, Windows logosu olan tuş). Veya ekranın sol alt köşesindeki **Başlat** (Windows simgesi) butonuna tıkla.
2. Açılan menüde **yazmaya başla**: `powershell` yaz (tek kelime, küçük harf yeterli).
3. Üstte **Windows PowerShell** yazısı çıkacak (mavi simgeli). Ona **tıkla** veya Enter’a bas.
4. Mavi veya siyah bir pencere açılacak; en altta `PS C:\Users\...>` gibi bir satır ve yanıp sönen çizgi var. **Komutları oraya yazacaksın.** Yazdıktan sonra **Enter**’a bas.

**Özet:** Windows tuşu → "powershell" yaz → Windows PowerShell’e tıkla → Açılan pencerenin en altındaki satıra komutları yaz, her komuttan sonra Enter.

---

## Adım 2: Proje klasörüne gir

Terminale **aynen** şunu yaz ve Enter’a bas:

```powershell
cd "c:\Users\CAGKAN CETINAR\Desktop\FEEDBACKTOME\feedback_to_me"
```

(Eğer proje başka bir yerdeyse, o yolu yaz.)

---

## Adım 3: Firebase’e giriş yap (sadece ilk sefer)

Şunu yaz ve Enter’a bas:

```powershell
firebase login
```

- Tarayıcı açılacak.
- Google hesabınla giriş yap (FeedbackToMe projesinin olduğu hesap).
- “Firebase’e erişim izni ver” / “Allow” gibi bir butona tıkla.
- Tarayıcıda “Giriş başarılı” gibi bir mesaj görünce **terminal penceresine dön**.
- Terminalde de “Success! Logged in as …” yazıyorsa bu adım tamam.

---

## Adım 4: Siteyi yükle

Aynı terminalde (yine `feedback_to_me` klasöründeyken) şunu yaz ve Enter’a bas:

```powershell
flutter build web
firebase deploy
```

- Birkaç saniye bekleyeceksin.
- En sonda “Hosting URL: https://feedbacktome-79655.web.app” yazacak.
- Bu linke tıklayınca yayındaki siteni göreceksin.

---

## Özet (sadece komutlar)

1. Terminal aç.
2. `cd "c:\Users\CAGKAN CETINAR\Desktop\FEEDBACKTOME\feedback_to_me"`
3. `firebase login` → tarayıcıda giriş yap, izin ver.
4. `firebase deploy` → bittikten sonra sitede gezinebilirsin.

---

## Sorun çıkarsa

### “firebase login” yazınca kırmızı hata çıkıyorsa

**1) “firebase tanınmıyor” / “is not recognized” yazıyorsa**  
Firebase CLI yüklü değil. Önce Node.js yüklü olmalı: [nodejs.org](https://nodejs.org) → LTS indir, kur. Sonra terminalde:
```powershell
npm install -g firebase-tools
```
Yazıp Enter’a bas. Kurulum bitince `firebase login` tekrar dene.

**1b) “running scripts is disabled” / npm.ps1 cannot be loaded**  
PowerShell script’lere izin vermiyor. **Önce** şunu çalıştır (tek seferlik):
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
“Y” yazıp Enter’a bas. Sonra `npm install -g firebase-tools` tekrar dene.

**2) “Cannot run login in non-interactive mode” yazıyorsa**  
Cursor’un içindeki terminal bazen tarayıcı açamıyor. Şunu yap:
- Windows **Başlat**’a “PowerShell” yaz.
- **Windows PowerShell**’i aç (Cursor’u kapatmana gerek yok).
- O pencerede: `cd "c:\Users\CAGKAN CETINAR\Desktop\FEEDBACKTOME\feedback_to_me"` yaz, Enter.
- Sonra `firebase login` yaz, Enter. Tarayıcı açılacak, giriş yap.
- Giriş tamamlanınca aynı PowerShell penceresinde `firebase deploy` yaz.

**3) Başka bir kırmızı hata**  
Terminaldeki kırmızı yazıyı (tamamını) kopyalayıp bir yere yapıştır; tam metne göre adım adım söyleyebilirim.

---

- **“Failed to authenticate”** dersen: Adım 3’ü (`firebase login`) tekrar yap, tarayıcıda girişi ve izni tamamla.
