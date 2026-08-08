# FEEDBACKTOME 2.0 — ARCHITECTURE AUDIT

> Salt-okuma denetim raporu. **Hiçbir kod değiştirilmedi.** Uygulama/refactor onay bekliyor.
> Tarih: 2026-08-08 · Branch: `feature/simple-summary-and-icon`

---

## 0. ÖNCE OKU — Vizyon ile Gerçeğin Ayrışması (kritik)

Verdiğin brief, ürünü bir **sosyal topluluk feedback platformu** olarak tanımlıyor:
feed, discover, follow, posts, reactions, ratings, **Supabase**, **Edge Functions**, RLS…

Bu repo **o ürün değil.** Repoda:

| Brief'te var | Repoda gerçek durum |
|---|---|
| Supabase + Edge Functions + RLS | ❌ Yok. **Firebase/Firestore** (varsayılan) + **Railway (Fastify+Prisma+Postgres)** ikinci backend |
| Feed / timeline | ❌ Yok |
| Discover / explore | ❌ Yok |
| Follow / follower grafiği | ❌ Yok ("follower" kelimesi yalnızca AI analiz metninde geçiyor) |
| Posts (herkese açık içerik) | ❌ Yok. İçerik hiç yüklenmiyor — uygulama medyayı **hiç görmüyor** |
| Community (başkaları senin postunu bulur) | ❌ Yok. Geri bildirim, **senin paylaştığın özel link** üzerinden gelir |
| Reactions | 🟡 Zayıf ilkel var: yorum formunda mood seçici (-1/0/1) |
| Ratings | 🟡 **Zaten var**: CreatorSurvey içinde beş adet 1–5 Likert puanı |
| AI yalnızca gerçek yorumları özetlesin | 🟡 Yarısı öyle (basit özet), yarısı değil (kapsamlı rapor kendi tavsiyesini üretiyor) |

**Sonuç:** Brief büyük ihtimalle başka bir proje için yazılmış jenerik bir şablon (Supabase/feed/discover bunun kanıtı). Ama **brief'in ruhu bu projeye uyuyor**: "AI teknik eleştirmen olmaktan çıksın; gerçek insanların kısa/sosyal/eğlenceli görüşlerini toplayıp özetlesin."

Bu yüzden rapor iki katmanı ayırıyor:
- **Uygulanabilir çekirdek** (mevcut link-paylaş modelini koruyarak feedback katmanını yeniden tasarlamak) → düşük risk, yüksek değer.
- **Sosyal ağ katmanı** (feed/discover/follow/community) → ayrı ve **çok daha büyük** bir ürün bahsi; mevcut altyapıda sıfırdan inşa gerektirir.

Raporun sonunda (Bölüm 16'dan sonra) bu **tek kritik kararı** senden isteyeceğim; çünkü yol haritasının şeklini o belirliyor.

---

## 1. Mevcut Mimari (Existing Architecture)

**İstemci:** Flutter. **Resmi state-management yok** — Provider/Riverpod/Bloc yok. Ham `StatefulWidget`+`setState`, Firebase/backend `Stream`'leri `StreamBuilder`/`FutureBuilder` ile bağlanıyor, bir de global `ValueNotifier` (locale).

**`app_state.dart`** bir "god object" değil; ~55 satır global singleton + yardımcı: `authService`, `iapService`, `appData` (backend seçici), `localeNotifier`, `effectiveDataOwnerId(...)`.

**Backend soyutlaması:** `AppDataBackend` arayüzü, iki uygulama:
- `FirestoreService` — **varsayılan / gerçek kaynak** (Firebase).
- `RailwayApiService` — Fastify+Prisma+Postgres REST.

Seçim **derleme-zamanı** flag'i: `USE_RAILWAY_API=true` + `API_BASE_URL` verilmezse Firestore çalışır (varsayılan). **İkisi arasında senkron/çift-yazma YOK** — build başına yalnızca biri canlı. Prisma şeması Firestore koleksiyonlarının paralel bir yeniden-uygulaması ("aligned with"), aynası değil.

**Auth her zaman Firebase** (backend fark etmeksizin). Railway modunda Firebase e-postası, geçici `/auth/dev/login` köprüsüyle Postgres JWT'sine çevriliyor (gerçek OAuth "sonra eklenecek" — `OAuthAccount` tablosu tanımlı ama **hiçbir route kullanmıyor** → ölü kod).

**Navigasyon:** Navigator 1.0, imperatif `push(MaterialPageRoute)`. Named route / go_router yok. Tek `MaterialApp`, `home: _AppLaunchGate`.

**Ödeme:** `in_app_purchase`, tek tüketilebilir ürün `premium_link_single`. **Sunucu-taraflı makbuz doğrulaması YOK** — istemci güvenilir kabul ediliyor.

## 2. Mevcut Kullanıcı Akışı (Existing User Flow)

1. Açılış → `_AppLaunchGate` (onboarding kontrolü) → `_AuthGate` (Firebase authState, timeout'la misafire de izin) → `LandingScreen`.
2. `LandingScreen`: 2 sekmeli `BottomNavigationBar` (Ana / Profil).
3. **Ana sekme:** aktif link varsa `_ActiveLinkHomeCard` → geri sayım + canlı yorum sayısı + büyük **Paylaş** + `_LiveSummaryLine` (tek satır "N kişi — çıkarım" önizleme). Süresi dolmuş link varsa `_LinkSummaryCard` (nihai özet). Hiçbiri yoksa `_CreateLinkHomeCard`.
4. **Giriş:** Google / Apple / "girişsiz devam".
5. **Link oluştur:** ilk link = demo (10 dk, tek yorum); sonrası premium (24 sa) — premium kredisi gerekiyorsa `PremiumScreen`.
6. **Paylaş:** `https://feedbacktome-79655.web.app/f/<code>` → `Share.share`.
7. **Yanıtlayan (misafir, girişsiz):** `FeedbackFormScreen` — link kodu, mood (-1/0/1), yorum metni, opsiyonel CreatorSurvey.
8. **Özet gör:** `AudienceAnalysisScreen` (basit) → içinden "Detaylı raporu gör" → `DetailedAudienceReportScreen` (kapsamlı).

## 3. Mevcut Feedback Motoru (Existing Feedback Engine)

Bir `Feedback` kaydı: `linkId`, `responderName?`, `relation?`, `mood` (-1/0/1), `textRaw`, `creatorSurvey?` (Json).

**Girdi katmanları (zaten mevcut!):**
- **Reaction ilkel:** mood seçici (3 durum) — brief'in istediği reaction setinin zayıf hali.
- **Rating:** `CreatorSurveyPayload` içinde **beş 1–5 Likert** (production/clarity/trust/engagement/consistency) + platform/sıklık/içerik-türü çoktan-seçmeli. **Opsiyonel, varsayılan kapalı** (collapsed ExpansionTile).
- **Kısa yorum:** `textRaw` (min 10 karakter — Firestore kuralı).

**İşleme:** `report_service.dart` yorumları koleksiyondan çeker; anahtar-kelime tema skorlama + `_calibratedMood` ile duygu; ardından iki farklı çıktı (bkz. Bölüm 4).

## 4. Mevcut AI Mimarisi (Existing AI Architecture)

**İki ayrı çıktı yolu var:**

**A) Basit özet — `generateSimpleRequestSummary` → `SimpleRequestSummary`** (brief'in istediğine yakın)
- `OpenAiAudienceClient.extractRequests`: yorumları 60'lık parçalarda işler (`_maxComments=300` tavan), her yoruma **konuya-özel kısa etiket + gerçek alıntı** üretir ("Saçını beğeniyor", "Ses kalitesini eleştiriyor").
- `_clusterLabels`: aynı-konu etiketlerini birleştirir (jenerik "Övgü/Eleştiri" **yasak**). **Sayım kodda yapılır.**
- → **AI kendi görüşünü üretmiyor**; gerçek yorumları etiketleyip kümeliyor. Bu, yeni vizyonun çekirdeği.

**B) Kapsamlı rapor — `generateAudienceAnalysis` → `CreatorIntelligenceReport`** (yeni vizyonla ÇELİŞEN)
- Önce `buildHeuristicCreatorReport` **tüm sayıları** üretir (skorlar, ısı haritası — deterministik, AI'sız).
- Sonra AI **metin katmanı** ekler: `collectPartialsDigest` → `refineCreatorIntelligence`. Persona: *"brutally honest content strategist and growth consultant."*
- AI şunları **kendi sesiyle yazıyor**: `comprehensiveCoachLetter` (koç mektubu), `topDiagnoses` (teşhisler), `actionPlan` (7g/30g/60g eylem planı), `segments`, `visualAndFormatInsight`, `riskOpportunity`.
- Prompt "her tavsiye gerçek yoruma dayansın, uydurma" diyor **ama tavsiyelerin kendisi (ne paylaş, nasıl büyü) modelin sentezi** — gerçek yorum değil.
- → **Brief'in yasakladığı tam olarak bu**: AI'nın uzman/danışman gibi kendi stratejik değerlendirmesini üretmesi.

**Önemli nüans:** AI, yaratıcının medyasını (video/foto) **hiç görmüyor**. "Teknik/görsel" dili ya anahtar-kelime tetiklemesi ya da yorumlarda geçenlerin parafrazı. Yani "typography/contrast" tipi bağımsız tasarım eleştirisi zaten yok; ama **koç mektubu + eylem planı + teşhis** formatı vizyonla çelişiyor.

**Güvenlik/altyapı:**
- Faz 1'de eklenen `POST /ai/chat` proxy (anahtar sunucuda) mevcut — istemci `AI_PROXY_URL` ile bunu çağırabiliyor. **Ama varsayılan build hâlâ anahtarı istemciye gömüyor** (proxy opsiyonel).
- **Demo generator** (`buildSyntheticFeedback`) şablon sahte yorumlar üretir — yalnızca `kDebugMode` Profil sekmesinden erişilir, release'de derlenmez. Ama üretilince gerçek `Feedback` dokümanı olarak yazılır (fake işareti yok).

## 5. Problemler (Yeni ürün vizyonuyla çelişenler)

1. **AI kendi tavsiyesini üretiyor** (kapsamlı rapor) — vizyonun 1 numaralı yasağı. `refineCreatorIntelligence` + `buildHeuristicCreatorReport` + `_heuristicCoachLetter`/`_topDiagnoses`/`_segmentInsights`.
2. **İki kimlikli ürün:** "basit sıcak özet" ile "kapsamlı danışman raporu" aynı uygulamada; kullanıcı hangisini kullanacağını bilmiyor. Müşteri geri bildirimi zaten "çok kapsamlı" demişti.
3. **Reaction sistemi ilkel:** 3 durumlu mood; brief'in istediği zengin/eğlenceli reaction seti (🔥❤️😍👀🤔😂🧐) yok, kategoriye göre değişebilir yapı yok.
4. **Rating gömülü ve gizli:** 5'li Likert var ama opsiyonel/kapalı; brief "tek genel skor, kolay/eğlenceli" istiyor — mevcut yapı teknik ve dağınık.
5. **Topluluk yok:** Vizyon "diğer GERÇEK kullanıcılar feedback verir" diyor; mevcut model yalnızca **senin link paylaştığın kişilerden** feedback alır. Feed/discover/community sıfır.
6. **Güvenlik açıkları:** IAP sunucu-doğrulaması yok; `PUT /me` istemcinin `isPremium`/`paidLinkCredits` set etmesine izin veriyor (bedava premium); Firestore feedback yazımı tamamen istemci-doğrulamalı; AI anahtarı hâlâ istemcide (proxy opsiyonel).
7. **Çift backend yarım:** Railway varsayılanda uykuda, OAuth köprüsü geçici, `OAuthAccount`/`textClean` ölü.
8. **AI maliyeti kontrolsüz:** `_LiveSummaryLine` her ana ekran yüklemesinde AI çağırabiliyor; summary cache'i kısmi (SharedPreferences), sunucuda source-hash bazlı cache yok.

## 6. KEEP (Aynen korunacak)

- **Auth** (Firebase Google/Apple + misafir yanıtlayan) — çalışıyor, dokunma.
- **Link modeli + 24 sa/demo yaşam döngüsü** (`FeedbackLink`, `validUntil`, `acceptsPublicFeedback`) — ürünün çekirdek mekanizması.
- **Misafir yanıt formu** (girişsiz feedback yazımı) — vizyonun "gerçek insanlar" değerinin taşıyıcısı.
- **Basit özet yolu** (`extractRequests` + `_clusterLabels` + `SimpleRequestSummary` + `SimpleRequestSummaryView`) — zaten "AI yalnızca gerçek yorumu özetler" ilkesine uyuyor.
- **Sunucu-taraflı AI proxy** (`server/src/routes/ai.ts`) — güvenli AI'nın temeli.
- **Tema, i18n (TR/EN), onboarding, paylaşım (Share/URL), ana ekran sadeleştirmesi**.
- **CreatorSurvey'in Likert altyapısı** — rating sistemine dönüştürülecek hammadde (silme, refactor).

## 7. REFACTOR (Düzenlenecek)

- **Mood seçici → Reaction sistemi:** 3 durumlu mood'u, generic ve genişletilebilir reaction setine çıkar (emoji tabanlı, kategoriye göre set). `mood` alanını geriye-dönük koru (pos/neu/neg türet).
- **CreatorSurvey (5 Likert) → tek "Crowd Score" + hafif reaction:** teknik 5'li puanı kullanıcıya tek basit skora indir; detaylı Likert'i opsiyonel/gizli tut ya da kaldır (karar Bölüm 9).
- **`SimpleRequestSummary` → `CommunityFeedbackSummary`:** brief'in JSON şemasına genişlet (`overallMood`, `headline`, `mostLiked`, `mostMentioned`, `mixedOpinions`, `hotTake`, `shortSummary`, `confidence`).
- **AI çağrısını sunucuya taşı:** istemci varsayılanı proxy yap; anahtarı istemciden tamamen kaldır.
- **Summary cache'i sunucuya + `source_hash`:** feedback değişmedikçe yeniden üretme.

## 8. REMOVE (Artık kullanılmayacak — hemen silme, işaretlendi)

- **Kapsamlı danışman raporu tümü** (vizyon yasağı):
  - `refineCreatorIntelligence`, `collectPartialsDigest` (openai_audience_client.dart)
  - `buildHeuristicCreatorReport`, `_heuristicCoachLetter`, `_heuristicVisualInsight`, `_topDiagnoses`, `_segmentInsights`, `mergeCreatorWithAiOverlay` (creator_intelligence_heuristic.dart)
  - `generateAudienceAnalysis` (report_service.dart), `DetailedAudienceReportScreen`, `CreatorIntelligenceReportView`, `creator_intelligence_report.dart`'ın danışman blokları (coachLetter/diagnoses/actionPlan/segments/visualInsight…)
  - `audience_score.dart` danışman alanları (executiveSummary vb.), snapshot'ın kapsamlı rapor gövdesi
- **Ölü backend:** `OAuthAccount` modeli (kullanılmıyor), `Feedback.textClean`, `saveAudienceScoreSnapshot.analyzedLinkId` (Railway'de düşüyor).
- **Not:** "Remove" = yeni üründe gösterilmeyecek. Kod fiziksel silme, migration'dan (Bölüm 15) sonra ve ayrı commit'te.

## 9. REPLACE (Yeni sistemle değiştirilecek)

| Eski | Yeni |
|---|---|
| `CreatorIntelligenceReport` (25+ alan danışman raporu) | `CommunityFeedbackSummary` (brief JSON: mood/headline/mostLiked/mostMentioned/mixed/hotTake/shortSummary/confidence) |
| `DetailedAudienceReportScreen` + `CreatorIntelligenceReportView` | `CommunityFeedbackView` (Community Score + Mood + Most Loved + Most Mentioned + Hot Take + Gerçek Yorumlar + Reaction dağılımı) |
| 5'li teknik Likert | Tek **Crowd Score** (ör. 8.4/10) |
| 3 durumlu mood | Reaction seti (🔥❤️😍👀🤔😂🧐), genişletilebilir |
| AI danışman/koç sesi | AI "yorumları yorumlayan" özetleyici sesi (bkz. Bölüm 13 kuralları) |

## 10. Önerilen FeedbackToMe 2.0 Mimarisi

**Kararına göre iki senaryo (Bölüm 16 sonrası soru):**

**Senaryo A — "Sosyal sunum, aynı model" (ÖNERİLEN, düşük risk):**
Mevcut link-paylaş 24 sa modelini KORU. Yalnızca **feedback katmanını** yeniden tasarla: zengin reaction + tek Crowd Score + kısa yorum + AI'nın **yalnızca özetleyen** community summary'si. Feed/discover/follow YOK. Firebase kalır. Brief'in "post it, see what people really think" hissini link modeliyle verir.

**Senaryo B — "Gerçek sosyal ağ" (yüksek risk, büyük bahis):**
Feed + discover + follow + herkese açık postlar inşa et. Bu; içerik yükleme (Storage), moderasyon, keşif algoritması, follow grafiği, bildirim altyapısı demek — **mevcutta hiçbiri yok**. Firebase Storage + ciddi yeni Firestore koleksiyonları + moderasyon gerekir. Bu bir "MVP re-write" ölçeğinde.

Feature-based hedef yapı (her iki senaryoda ortak, kademeli):
```
lib/
  core/ (config, routing, theme, services)
  shared/ (models, widgets, services)
  features/
    auth/ onboarding/ link/ (create+share)
    feedback/
      data/ (repository) domain/ (models) presentation/ (widgets) services/
        ReactionService · RatingService · CommentService
        FeedbackRepository · FeedbackAggregationService · FeedbackSummaryService
    profile/ settings/
```
Mevcut proje tek-dosya-ağırlıklı (`main.dart` ~5000 satır). Feature-based geçiş **kademeli** olmalı; tek seferde büyük taşımadan kaçın.

## 11. Önerilen Kullanıcı Akışı

**Senaryo A:**
Aç → (misafir de olabilir) → Link oluştur → 24 sa paylaş → Yanıtlayanlar: **reaction + tek skor + kısa yorum** ("İlk aklına geleni yaz") → Sahibe canlı: `41 🔥 · 28 ❤️ · 7 🤔 · 8.4/10 · 32 yorum` → süre sonunda **Community Summary** (mood + en sevilen + en çok konuşulan + hot take + gerçek yorumlar).

**Senaryo B:** yukarıya ek olarak feed/discover/follow/post yükleme akışları (yeni, büyük).

## 12. Veritabanı Değişiklikleri

**Yeni tablo GEREKMİYOR (Senaryo A) — mevcut yapı yeter, minimal ekleme:**
- `Feedback`: `reactions` alanı (mevcut `mood`'u koru; yeni `reaction` string ekle — geriye dönük).
- Yeni **`feedback_summaries`** (brief'in önerdiği, cache için): `id`, `linkId`(veya `ownerId`), `summary_json`, `comment_count`, `rating_count`, `reaction_count`, `generated_at`, `model_version`, `source_hash`. Firestore'da `links/{id}/summary/current` veya `summaries/{linkId}` dokümanı olarak.
- `source_hash`: feedback kümesi değişmedikçe AI özetini yeniden üretme (maliyet).
- **Sil (migration sonrası):** `OAuthAccount`, `Feedback.textClean`, kapsamlı snapshot alanları.

**Senaryo B ek:** `posts`, `follows`, `post_reactions`, moderasyon tabloları + Firebase Storage → büyük.

## 13. Yeni AI Mimarisi

**Tek AI görevi:** structured input (post/link istatistikleri + gerçek yorumlar) → `CommunityFeedbackSummary` JSON.

Input: `feedbackCount`, `ratingAvg`, `reactionCounts`, `realComments[]`.
Output (brief JSON):
```json
{
  "overallMood": "positive|mixed|neutral|negative",
  "headline": "İnsanlar genel olarak sevmiş 🔥",
  "mostLiked": ["Renkler", "Genel görünüm"],
  "mostMentioned": ["Yazı biraz daha belirgin olabilir"],
  "mixedOpinions": [],
  "hotTake": "Direkt startup logosu gibi 😂",
  "shortSummary": "Genel hava olumlu; özellikle renkler dikkat çekmiş.",
  "confidence": "low|medium|high"
}
```
**Sistem kuralları (prompt):** içeriği bağımsız değerlendirme; yalnızca gerçek yorumları analiz et; söylenmeyen sorun üretme; teknik/UX jargonu yok; akademik dil yok; kısa+samimi; az yorumda kesin yargı yok ("birkaç kişi kararsız"); tek negatiften genelleme yok; çelişki varsa "topluluk ikiye bölünmüş" de; **AI yorum üretmez, yorumları yorumlar.**

**Güvenlik:** çağrı **yalnızca `server/src/routes/ai.ts` üzerinden** (anahtar sunucuda); prompt-injection için yorumlar "veri" olarak işaretlenir; `source_hash` cache; min-feedback tetikleyici (ör. ≥3), N yeni feedback'te veya kullanıcı özeti açıp cache eskiyse yenile.

## 14. Dosya Değişiklikleri (dokunulacaklar)

**Refactor/Replace (istemci):**
- `lib/services/openai_audience_client.dart` — danışman metodlarını çıkar; `summarizeCommunity()` ekle; proxy varsayılan.
- `lib/services/report_service.dart` — `generateAudienceAnalysis` kaldır; `SimpleRequestSummary`→`CommunityFeedbackSummary`.
- `lib/models/creator_intelligence_report.dart` → yeni `community_feedback_summary.dart`.
- `lib/models/feedback_entry.dart` — `reaction` alanı.
- `lib/widgets/simple_request_summary_view.dart` → `community_feedback_view.dart`.
- `lib/main.dart` — `FeedbackFormScreen` (reaction+skor), `DetailedAudienceReportScreen` kaldır, ana ekran özet kartı.
- Yeni: `ReactionService`, `RatingService`, `FeedbackAggregationService`, `FeedbackSummaryService`, `FeedbackSummaryCache`.

**Sunucu:**
- `server/src/routes/ai.ts` — `POST /ai/summary` (structured, cache, injection guard).
- `server/src/routes/users.ts` — `isPremium`/`paidLinkCredits` istemci-yazımını kapat (güvenlik).
- IAP doğrulama route'u (Faz 2).
- Prisma: `feedback_summaries`, `Feedback.reaction`; ölüleri kaldır.

**Sil (geç aşama):** `creator_intelligence_heuristic.dart`, `creator_intelligence_report_view.dart`, `audience_score*` danışman kısımları.

## 15. Migration Stratejisi (veri/kullanıcı kaybı olmadan)

1. **Kimse silinmez önce.** Yeni model/servisleri **eski yanında** (feature flag `USE_COMMUNITY_SUMMARY`) ekle.
2. Eski `Feedback` dokümanları aynen çalışır: `reaction` yoksa `mood`'dan türet; `creatorSurvey` Likert'i tek Crowd Score'a indir.
3. Eski snapshot/rapor verisi **okunabilir kalır** (read-only); yeni özet ayrı yola yazılır.
4. Yeni akış onaylanınca eski ekranları UI'dan kaldır (kod hâlâ dursun).
5. Son adım: ölü kodu ayrı "cleanup" commit'inde fiziksel sil.
6. Her faz **ayrı commit + `flutter analyze` temiz**; geri alınabilir.

## 16. Uygulama Yol Haritası

Her görev: **amaç · dosyalar · DB etkisi · risk · test · tamamlanma kriteri.**

### P0 — Kritik

**P0.1 — AI'yı sunucuya kilitle (anahtar istemciden kalksın)**
- Amaç: sızıntı/maliyet/injection tek hamlede.
- Dosyalar: `openai_audience_client.dart` (proxy varsayılan), build flag'leri.
- DB: yok. · Risk: düşük (proxy zaten var). · Test: web+mobil özet üretimi, istemcide anahtar yok. · Kriter: `AI_PROXY_URL` zorunlu, direkt çağrı kapalı.

**P0.2 — Bedava-premium açığını kapat**
- Amaç: `PUT /me` ile `isPremium`/`paidLinkCredits` yazımını engelle; IAP sunucu-doğrulaması.
- Dosyalar: `server/routes/users.ts`, yeni IAP verify route, `iap_service.dart`. · DB: yok/opsiyonel receipt tablosu. · Risk: orta. · Test: sahte kredi denemesi reddedilir. · Kriter: kredi yalnızca doğrulanmış makbuzla.

**P0.3 — AI danışman raporunu kapat (vizyon yasağı)**
- Amaç: kapsamlı rapor yolunu üretimden kaldır (feature flag).
- Dosyalar: `report_service.dart`, `DetailedAudienceReportScreen` girişini gizle. · DB: yok. · Risk: düşük. · Test: hiçbir yerde koç mektubu/eylem planı görünmüyor. · Kriter: yalnızca community summary erişilebilir.

### P1 — Yüksek

**P1.1 — `CommunityFeedbackSummary` modeli + AI özeti (structured JSON)**
- Dosyalar: yeni model, `openai_audience_client.summarizeCommunity`, `POST /ai/summary`. · DB: `feedback_summaries` + `source_hash`. · Risk: orta. · Test: sabit yorum kümesi → beklenen JSON; cache hit. · Kriter: brief JSON şeması, kurallara uyum.

**P1.2 — Reaction sistemi (mood → emoji seti)**
- Dosyalar: `feedback_entry.dart` (`reaction`), `FeedbackFormScreen`, `ReactionService`. · DB: `Feedback.reaction`. · Risk: düşük (geriye dönük). · Test: eski `mood` kayıtları hâlâ okunuyor. · Kriter: 🔥❤️😍👀🤔😂🧐 seti çalışır, dağılım gösterilir.

**P1.3 — Tek Crowd Score + Community Feedback UI**
- Dosyalar: `RatingService`, `community_feedback_view.dart`, ana ekran kartı. · DB: yok. · Risk: düşük. · Test: skor + mood + most loved/mentioned + hot take + gerçek yorumlar render. · Kriter: brief UI şablonu.

### P2 — İyileştirme

**P2.1** — Summary cache + akıllı tetikleyici (min feedback, N-yeni, cache-eskime) → maliyet.
**P2.2** — Firestore güvenlik kuralları sıkılaştırma (feedback yazım limiti, spam koruması).
**P2.3** — Ölü kod temizliği (ayrı commit): `OAuthAccount`, `textClean`, kapsamlı rapor dosyaları.
**P2.4** — Feature-based dizin taşıması (kademeli).
**P2.5** — (Senaryo B seçilirse) feed/discover/follow — ayrı epik, ayrı planlama.

---

## KARAR GEREKLİ (uygulamaya başlamadan)

Yol haritasının şekli tek bir seçime bağlı:
- **Senaryo A** — Mevcut link-paylaş modelini koru, yalnızca feedback katmanını sosyal/eğlenceli/özet-odaklı yeniden tasarla (düşük risk, hızlı, brief'in ruhuna uyar).
- **Senaryo B** — Gerçek sosyal ağ (feed/discover/follow/post yükleme) inşa et (yüksek risk, MVP-rewrite ölçeği, yeni altyapı).

Onayın ve senaryo seçimin gelince P0'dan başlayacağım.
