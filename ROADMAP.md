# Feedback2Me — Yol Haritası

## Vizyon
Kendi adına tek bir link oluştur → **24 saat** boyunca herkes anonim yorum yazsın →
süre sonunda **basit, sıcak, konuya-özel ve gruplanmış** bir özet çıksın
("N kişi saçını boyatmanı istiyor" + gerçek yorum alıntıları). Kapsamlı değil; keyifli.

## Şu anki durum (özet)
- ✅ Çekirdek döngü çalışıyor: link → topla → sıcak/gruplanmış özet.
- ✅ AI gerçekten çalışıyor (json 400 kök-nedeni çözüldü), konuya-özel + kümelemeli + gerçek alıntılı.
- ✅ Ana ekran sadeleşti; yeni F2M ikonu.
- ⚠️ OpenAI anahtarı istemciye gömülü; maliyet kontrolsüz; IAP sunucu-doğrulaması yok; injection/spam koruması yok; iki backend yarım; kapsamlı rapor vizyonla çelişiyor.

---

## Fazlar (öncelik sırası)

### Faz 0 — Güvene alma
**Neden:** Uzun süredir commit yok; büyük emek kaybı riski.
**Ne:** Biriken çalışmayı mantıklı commit'lere böl (ikon/splash · basit özet özelliği · AI düzeltmeleri).
**Kabul:** `git status` temiz; her şey versiyon altında.

### Faz 1 — Sunucu-tarafı AI (EN YÜKSEK ÖNCELİK)
**Neden:** Tek hamlede 5 sorunu çözer: anahtar sızıntısı, CORS, rate-limit, maliyet tavanı, prompt-injection.
**Ne:**
- `server/` (Railway Fastify) altına `POST /ai/takeaways` endpoint'i: yorumları alır, OpenAI'yi **sunucuda** çağırır (anahtar sunucu env'inde), çıkarım + kümeleme + sayımı döndürür.
- İstemci (`OpenAiAudienceClient`) doğrudan OpenAI yerine bu endpoint'i çağırır (anahtar istemciden kalkar).
- Endpoint'te: **rate-limit**, **prompt-injection filtresi** (yorumlar veri olarak işaretlenir), **özet önbelleği**.
**Kabul:** İstemcide anahtar yok; web'de proxy'siz çalışır; aynı yorum kümesi tekrar işlenmez.

### Faz 2 — Gelir & veri güvenliği
**Neden:** Bedava premium üretimi ve doğrudan veri istismarı riski.
**Ne:**
- IAP **sunucu-tarafı makbuz doğrulaması** (App Store / Play).
- **Firestore güvenlik kuralları**: kredi/premium alanları yalnızca sunucudan yazılır; feedback yazımı sınırlı.
**Kabul:** Sahte kredi üretilemez; kurallar testlerle doğrulanır.

### Faz 3 — Ürün netliği (tek kimlik)
**Neden:** "Basit" vizyon ile "kapsamlı rapor" çelişiyor; kullanıcı kararsız kalıyor.
**Ne:**
- Kapsamlı raporu ya kaldır ya "meraklısına" gizli premium ek yap.
- **Düşük hacim** deneyimini mükemmelleştir (0–5 yorum çoğunluk).
- **Paylaşım döngüsü**: "linke yanıt yaz" akışı tek dokunuş, girişsiz, akıcı.
**Kabul:** İlk açılışta kullanıcı ne yapacağını 3 saniyede anlıyor.

### Faz 4 — Ölçek & maliyet guardrail'leri
**Neden:** Tek satın alma, binlerce yorumluk AI maliyetini karşılamayabilir.
**Ne:**
- Link başına işlenen yorum tavanı + örnekleme şeffaflığı ("~300 yorum üzerinden").
- Canlı önizlemeyi önbelleğe al (her açılışta AI çağırma).
- Birim ekonomi gözden geçirme.
**Kabul:** Maliyet, yorum hacminden bağımsız öngörülebilir.

### Faz 5 — Uyum & büyüme
**Ne:** KVKK/GDPR (veri saklama, silme hakkı, rıza) · süre-sonu push bildirimi · retention kancası.
**Kabul:** Yasal uyum sağlanır; kullanıcıyı geri getiren en az bir mekanizma çalışır.

---

## Sıra
Faz 0 → Faz 1 → Faz 2 → Faz 3 → (Faz 4 & 5 paralel).
Her faz bağımsız değer üretir; Faz 1 tamamlanınca ürün "yayına gerçekten hazır" olur.
