# Firestore Rules — Lifecycle Testleri

`../../firestore.rules` içindeki feedback lifecycle invariant'larını Firestore
emulator üzerinde doğrular. **Java gerektirir** (emulator runtime).

## Çalıştırma

```bash
# 1) test bağımlılıkları
cd test/rules && npm install && cd ../..

# 2) emulator içinde testler (repo kökünden)
firebase emulators:exec --only firestore "node --test test/rules"
```

## Kapsam

| # | Senaryo | Beklenen |
|---|---------|----------|
| 1 | active demo + feedback + atomic consume batch | ALLOW |
| 2 | active demo + yalnız feedback create (link kapatılmaz) | DENY |
| 3 | demo already used + feedback | DENY |
| 4 | expired demo | DENY |
| 5 | demo create validUntil > cap (20 dk) | DENY |
| 6 | active premium feedback | ALLOW |
| 6b | premium çoklu feedback | ALLOW |
| 7 | expired premium feedback | DENY |
| 8 | premium create validUntil > cap (30 gün) | DENY |
| 9 | normal 24 saat premium create | ALLOW |
| 10 | normal 10 dk demo create | ALLOW |
| 11 | owner reactivate (isActive false→true) | DENY |
| 12 | owner validUntil uzatma | DENY |
| 13 | owner demoSubmissionUsed reset | DENY |
| 14 | owner deactivate (isActive true→false) | ALLOW |

## Not

Bu testler bir üretim bağımlılığı DEĞİLDİR; yalnız güvenlik kurallarını
kilitler. Ana Flutter uygulaması ve `functions/` bu paketi kullanmaz.
