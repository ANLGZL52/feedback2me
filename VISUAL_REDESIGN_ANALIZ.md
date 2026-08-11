# FEEDBACK2ME — GÖRSEL YENİDEN TASARIM · MİMARİ ANALİZ RAPORU (Bölüm 39)

> **Salt-okuma analiz.** Hiçbir dosya değiştirilmedi, hiçbir kod yazılmadı.
> Amaç: iş mantığını/backend'i KORUYARAK görsel yeniden tasarım öncesi zemini çıkarmak.
> Tarih: 2026-08-11

---

## 0. Hedef tasarım özeti (mockup A/B/C + prompt)

Aydınlık tema · warm-white zemin (#F7F8FC/#FFFFFF) · **mavi→mor gradient** primary (#3557F6→#7555F8) ·
yumuşak gölgeler · 20–24px kart radius · güçlü whitespace · samimi 3D illüstrasyon · tek dominant CTA ·
TR/EN toggle. Mevcut **siyah + altın + koyu mor** dil tamamen bırakılıyor.

**⚠️ Mockup ile prompt arasındaki çelişkiler (prompt kazanır):**
- **Premium ekranı (mockup C-15)** "Aylık/Yıllık · 99 TL/ay" abonelik gösteriyor. **Prompt (30. madde):
  abonelik EKLEME, kredi-tabanlı kal, fiyatı hardcode etme.** → Abonelik UI'ı yapılmayacak; mevcut
  "link kredisi" modeli korunacak, fiyat IAP'den gelecek.
- **Bildirimler (mockup C-14 Settings satırı):** mevcut üründe bildirim altyapısı YOK. → satır ya gizlenir
  ya da işlevsiz placeholder olur (yeni sistem kurulmaz).
- **Web sitesi/URL bağlamı (mockup B-7 "demo.site.com Web Sitesi Hakkında Geri Bildirim"):** yalnızca
  illüstratif örnek. Prompt: URL/web analizi EKLEME. → link sahibinin adı/başlığı gösterilir, web analizi yok.

---

## A. Mevcut Flutter mimarisi

- **State management: yok** (Provider/Riverpod/Bloc yok). Ham `StatefulWidget`+`setState`, Firebase/backend
  `Stream`'leri `StreamBuilder`/`FutureBuilder` ile; global `ValueNotifier` (locale).
- **Global servis erişimi:** `app_state.dart` — `authService`, `appData` (backend seçici), `iapService`,
  `localeNotifier` singleton globalleri.
- **Backend soyutlaması:** `AppDataBackend` arayüzü, iki uygulama (`FirestoreService` = varsayılan/canlı,
  `RailwayApiService` = derleme-zamanı flag'iyle, uykuda).
- **Navigasyon:** Navigator 1.0, imperatif `push(MaterialPageRoute)`. Named route/go_router YOK.
- **En kritik yapısal gerçek: `lib/main.dart` ~5200 satır — bir monolit.** Tüm ekranlar + ana-ekran
  alt-widget'ları + auth gate'leri + tema sarmalayıcısı burada.

## B. Mevcut ekran widget'ları ve dosyaları

**`main.dart` içindeki ekranlar (public):**
`LoginScreen` · `LandingScreen` (ana ekran, 2 sekmeli: Ana/Profil) · `CreateProfileScreen` ·
`CreatedLinkScreen` (link oluşturuldu) · `DashboardScreen` · `AudienceAnalysisScreen` (topluluk özeti —
canlı/varsayılan) · `DetailedAudienceReportScreen` (kapsamlı rapor — flag'le kapalı) · `ReportAnalysisScreen` ·
`SavedAudienceReportScreen` · `FeedbackFormScreen` (feedback yaz).

**`main.dart` içindeki ana-ekran alt-widget'ları (private):**
`_CreateLinkHomeCard` · `_ActiveLinkHomeCard` · `_LiveSummaryLine` · `_LinkSummaryCard` · `_AppBrand` ·
`_PrimaryActions` · `_FooterNote` · `_LinkTierHeaderBadge` · `_ProfileTab` · `_FeedbackPoolCard` ·
`_ActiveLinkPoolContent` · `_ExpiredLinkPoolContent` · `_AllCommentsScreen` · `_AudienceAnalysisLoadingPanel` ·
`_ReportSharePreviewCard`. Gate'ler: `_WebSplash` · `_WebInitWrapper` · `_AppLaunchGate` · `_AuthGate`.

**Ayrı dosyalardaki ekran/görünümler:**
`screens/settings_screen.dart` · `screens/premium_screen.dart` · `widgets/app_onboarding.dart` (onboarding) ·
`widgets/community_feedback_view.dart` (AI topluluk özeti UI) · `widgets/simple_request_summary_view.dart` ·
`widgets/creator_intelligence_report_view.dart` (kapsamlı rapor — kapalı) · `widgets/audience_score_widgets.dart` ·
`widgets/creator_survey_section.dart` · `widgets/link_validity_countdown.dart` (geri sayım) ·
`widgets/link_plan_banner.dart` · `widgets/feedback_link_tile.dart`.

## C. Routing / navigation sistemi

- Navigator 1.0 imperatif push. Tek `MaterialApp`, `home: _AppLaunchGate`.
- Zincir: `_AppLaunchGate` (onboarding kontrolü) → `_AuthGate` (Firebase authState + timeout, misafire izin) →
  `LandingScreen`. `LandingScreen` içinde `BottomNavigationBar` (Ana/Profil), sekme `setState` ile.
- Deep-link/URL route yok (mobil paylaşım linki dağıtımdaki `f.html` üzerinden; uygulama içi route yok).
- **Redesign etkisi:** görsel; bottom-nav yeniden tasarlanır. Route yapısını değiştirmek gerekmez (prompt 35:
  gereksiz tab ekleme). İstenirse Ana/Profil'e "Linkler" eklemek ancak mevcut veriyle desteklenirse (bkz. N).

## D. Theme sistemi

- `theme/app_theme.dart` — sabit marka renkleri: `gold #E8C547`, `goldDark #D4AF37`, `cardBg #121215`,
  `appBarBg/navBarBg #0D0D0D`.
- `theme/feedback_material_theme.dart` — `buildFeedbackTheme()`: **yalnızca koyu** (`brightness: dark`),
  M3, altın primary, koyu kart teması, `scaffoldBackgroundColor` (bu oturumda `#141210`'a çekildi).
- Koyu zemin bazı ekranlarda `_DarkMysticalBackground` (mor gradient) ile veriliyor; bazıları scaffold zeminine
  güveniyor.
- **Redesign etkisi (en büyük iş):** bu koyu-only tema + altın dil TAMAMEN yeni **aydınlık design system** ile
  değiştirilecek. `_DarkMysticalBackground` kaldırılıp aydınlık/soft gradient zemine dönüşecek.

## E. Kullanılan reusable UI component'ları

- **Merkezi component kütüphanesi YOK.** Ekranların içinde satır-içi `Card`, `FilledButton`, `OutlinedButton`,
  `TextField`, `Container` + tekrar eden `EdgeInsets`/`BorderRadius`/`TextStyle`/`Color` kullanımı yaygın.
- Yarı-paylaşık parçalar: `link_validity_countdown.dart`, `link_plan_banner.dart`, `feedback_link_tile.dart`,
  `audience_score_widgets.dart`, `community_feedback_view.dart` (kendi içinde `_Card`/`_ChipsCard`/`_SectionLabel`).
- **Redesign etkisi:** merkezi design-system + paylaşık component seti kurulması gereken en kritik refactor (bkz. Q).

## F. Firebase/backend ile doğrudan bağlı widget'lar

- `LandingScreen` (`_LandingScreenState`): `appData.linksForOwnerStream`, `feedbacksForLinkStream`,
  `userProfileStream` StreamBuilder'ları + `_createLink` link-oluşturma mantığı **inline**.
- `_LiveSummaryLine`/`_LinkSummaryCard`: `reportService.generateCommunitySummary` çağrısı inline.
- `AudienceAnalysisScreen`/`_AudienceAnalysisScreenState`: özet üretimi + `CommunitySummaryStore` cache inline.
- `FeedbackFormScreen`: `appData.addFeedback` + `_parseLinkCode` + `_submit` mantığı inline.
- `CreateProfileScreen`: `appData.setUserProfile` inline. `_ProfileTab`: profil stream + debug seed inline.
- `premium_screen.dart`: `iapService.loadProducts/startPurchase/restore` + debug +1 kredi inline.
- **Redesign etkisi:** bu ekranlarda görsel değişirken **iş mantığı çağrılarına dokunulmamalı**; UI'ı
  logic'ten ayırmadan sadece görünümü sarmak riskli (bkz. O, P).

## G. Mevcut link oluşturma mantığı (DEĞİŞMEYECEK)

- `AppDataBackend.createLink` → `FirestoreService._computeLinkForCreate`: ilk link **demo** (10 dk, tek yorum,
  `freeDemoLinkUsed=true`); aktif premium/kredi varsa **premium** (24 saat, `paidLinkCredits` −1); yoksa
  `link_requires_credit`. `FeedbackLink` modeli: `linkTier`, `validUntil`, `demoSubmissionUsed`, `isActive`.
- UI tetikleyici: `LandingScreen._createLink` (aktif link uyarısı, retry, kredi snackbar → `PremiumScreen`,
  kopyala + `CreatedLinkScreen`).
- **Redesign:** yalnızca `_createLink`'i çağıran ekran/kart yeniden tasarlanır; `_computeLinkForCreate`
  ve model **aynı kalır**.

## H. Demo / premium iş mantığı (DEĞİŞMEYECEK)

- `UserProfile`: `isPremium`, `premiumUntil`, `freeDemoLinkUsed`, `paidLinkCredits`; türetilen
  `hasFreeDemoAvailable`, `canCreatePaidPremiumLink`.
- Demo=10 dk/tek yorum, premium=24 saat/çoklu. `validUntil` + `acceptsPublicFeedback` (isActive & süre & demo-tek-kullanım).
- **Redesign:** demo↔premium farkı mockup A-4'teki iki kart (Demo/Premium) ile daha güçlü **gösterilir**;
  süre/kredi kuralları koda dokunulmadan korunur.

## I. Feedback gönderme mantığı (DEĞİŞMEYECEK)

- `FeedbackFormScreen._submit` → `_parseLinkCode(code)` → `appData.getLinkByCode` → `appData.addFeedback(
  linkId, mood, reaction, textRaw, creatorSurvey…)`.
- `addFeedback` arayüz + Firestore/Railway uygulamaları: demo tek-kullanımda linki kapatır; kurallar
  `textRaw>=10` + `acceptsPublicFeedback`.
- Reaction seti `config/feedback_reactions.dart` (`kDefaultReactions`: fire/love/wow/eyes/hmm/fun/meh); seçim
  hem `reaction` hem (geriye dönük) `mood` yazar.
- **Redesign:** reaction/rating/yorum ADIMLARI mockup B-8/9 gibi yeniden tasarlanır; **reaction anahtarları,
  mood türetme, addFeedback imzası aynı kalır** (backend uyumu).

## J. AI özet veri modeli (DEĞİŞMEYECEK — görselleştirilecek)

- `report_service.generateCommunitySummary(ownerId/linkId)` → yorumları toplar → reaction/duygu sayımı
  (`ReactionService`) → Crowd Score (`RatingService`) → `extractRequests` + `summarizeCommunity`
  (`OpenAiAudienceClient`, anahtar **sunucuda** proxy — P0.1) → `CommunityFeedbackSummary`.
- `CommunityFeedbackSummary` alanları: `mood`, `headline`, `mostLiked`, `mostMentioned`, `mixedOpinions`,
  `hotTake`, `shortSummary`, `confidence`, `crowdScore`, `feedbackCount`, `positive/neutral/negative`,
  `reactionCounts`, `realComments`, `aiUsed`. Cache: `community_summary_store.dart` (süresi dolan link).
- Mevcut UI: `community_feedback_view.dart` (`CommunityFeedbackView`).
- **Redesign:** mockup C-11 (Topluluk Skoru + **duygu dağılımı donut** [positive/neutral/negative'den türer] +
  sevilen/konuşulan/bölünenler + hot take + genel AI özeti). **Tüm alanlar mevcut modelde var** → yeni metrik
  uydurmadan görselleştirilir. Donut = mevcut pos/neu/neg sayımlarından.

## K. Profil veri modeli

- `UserProfile` (users/{uid}): displayName, email, photoUrl, handle, isPremium, premiumUntil, freeDemoLinkUsed,
  paidLinkCredits, createdAt. Mevcut Profil ekranı (`_ProfileTab`) çok sade + debug seed araçları.
- Mockup C-13 istatistikleri (**Toplam Link / Toplam Yorum / Ortalama Skor**) ve **Link Geçmişi** doğrudan
  alanlarda yok AMA **mevcut veriden türetilebilir**: `linksForOwnerStream` (linkler) + link başına feedback
  sayısı/skoru (mevcut sorgular). "Pro Kullanıcı" rozeti = isPremium/kredi.
- **Redesign:** yeni profil bu türetilebilir verilerle kurulur; **yeni koleksiyon/şema GEREKMEZ** (yalnızca
  toplama sorguları). Türetilemeyen bir metrik varsa gösterilmez.

## L. Localization sistemi

- **ARB DEĞİL** — `l10n/app_localizations.dart` içinde **özel harita**: `L10n.get(context, 'key')`,
  `L10n.languageCodeForApp`, `localeNotifier` ile TR/EN + cihaz dili; SharedPreferences ile kalıcı.
- **Prompt 31:** "Mevcut sistem ARB ise ARB, değilse mevcut sistemi sürdür." → **Mevcut harita sistemi
  korunacak**; yeni metinler bu haritaya TR+EN olarak eklenecek. Hardcoded metin bırakılmayacak.

## M. Responsive / web yapısı

- Uygulama Flutter mobil + web. Web'de ekranlar dar tek-kolon merkezde (bazı yerlerde `maxWidth ~400–440`),
  masaüstünde geniş boş alan (kullanıcının şikayeti).
- Global responsive/breakpoint sistemi yok; `device_preview` (dart-define ile) mevcut.
- **Redesign (prompt 36):** mobil-first; masaüstünde dashboard 2-kolon, auth/feedback ~440–520 merkez,
  AI özet ~900–1100 geniş. Ortak component'lerden responsive üretim.

## N. Yalnızca görsel refactor edilebilecek ekranlar (düşük risk)

Bunlar ağırlıkla sunum; iş mantığı çağrıları korunarak yeniden temalanabilir:
- **Splash / Onboarding** (`_WebSplash`, `app_onboarding.dart`) — davranış aynı, tam görsel yenileme.
- **LoginScreen** — auth çağrıları aynı, tasarım yeni (mockup A-3). E-posta girişi ekranı mockup'ta var ama
  **mevcut auth yalnız Google/Apple/misafir** → e-posta/kayıt eklemek backend değişikliği olur; prompt "auth
  rewrite yapma" diyor → e-posta girişi **eklenmez** (yalnız Google/Apple/misafir yeniden tasarlanır).
- **Misafir & girişli ana ekran kartları** (`_CreateLinkHomeCard`, `_PrimaryActions`, `_FooterNote`) —
  aksiyonlar aynı, mockup A-2/A-5 dili.
- **CreatedLinkScreen** (mockup A-5 başarı ekranı) — auto-copy davranışı korunur; QR **yalnızca** kolay ve
  kapsam-içi ise önerilir, aksi halde eklenmez.
- **Premium/Link kredisi ekranı** — abonelik EKLENMEDEN (bkz. 0), kredi modeli yeni kartlarla.
- **Settings** (`settings_screen.dart`) — dil/hesap/çıkış aynı, mockup C-14 düzeni.
- **CommunityFeedbackView / AudienceAnalysisScreen** — model aynı, mockup C-11 görselleştirmesi.

## O. UI ile iş mantığının fazla bağlı olduğu ekranlar (yüksek dikkat)

- **`LandingScreen` (ana ekran):** link-oluşturma mantığı (`_createLink`: uyarı diyaloğu, retry, kredi
  yönlendirmesi) + üç StreamBuilder inline. Aktif/pasif link kartı seçimi burada. Redesign'da UI'ı sararken
  bu akış kırılabilir.
- **`FeedbackFormScreen`:** `_parseLinkCode` + `_submit` + reaction/mood/anket toplama tek dosyada; adımlı
  (reaction→rating→yorum) mockup akışına dönüştürürken submit sözleşmesi korunmalı.
- **`AudienceAnalysisScreen`:** özet üretimi + cache + hata/boş/yükleme durumları iç içe.
- **`_ProfileTab`:** profil stream + debug seed + (yeni) istatistik/geçmiş toplama.
- **`premium_screen.dart`:** IAP yaşam döngüsü (loadProducts/startPurchase/restore/creditGranted stream) UI'a gömülü.

## P. Görsel redesign sırasında kırılma riski olan noktalar

1. **`main.dart` monoliti** — ekranları ayrı dosyalara taşırken import/state bağları kopabilir (öneri: taşımadan
   önce her ekranı izole edilebilir hale getir; küçük adımlar + her adımda `flutter analyze`).
2. **Tema anahtarı** — koyu→aydınlık geçişinde `_DarkMysticalBackground`'a ve sabit beyaz/`white70` metin
   renklerine bağlı her yer görünmezleşebilir (bu oturumda AudienceAnalysis/Premium'da yaşandı). Tüm renkler
   design-system token'larına çekilmeli.
3. **`_createLink` akışı** — kredi/demo yönlendirmesi ve `CreatedLinkScreen` push zinciri.
4. **Feedback submit sözleşmesi** — reaction anahtarları + mood + `addFeedback` imzası.
5. **Localization** — yeni metinlerin TR+EN eklenmemesi → eksik/karışık dil.
6. **AI özet alan eşlemesi** — donut/etiketler yalnız mevcut `CommunityFeedbackSummary` alanlarından; uydurma yok.
7. **Web/responsive** — mevcut sabit `maxWidth` varsayımları masaüstünde bozulabilir.
8. **Debug araçları** — production'da gizli kalmalı (kDebugMode guard korunmalı/güçlendirilmeli).

## Q. Oluşturulması gereken design-system dosyaları

Yeni `lib/design_system/` (veya mevcut `theme/` genişletilerek):
- `app_colors.dart` — aydınlık paleti (bg #F7F8FC/#FFFFFF, primary #3557F6, gradient #3458F5→#7555F8,
  secondary #7357F6, success #37C98B, warning #F8B83E, text #111735/#68708C, surface, border #E7E9F2) +
  koyu varyant opsiyonel.
- `app_typography.dart` — Display 32–36 / Title 24–28 / Card 18–20 / Body 15–16 / Secondary 14 / Caption 12–13,
  weight hiyerarşisi.
- `app_spacing.dart`, `app_radius.dart` (kart 20–24, input 14–16, chip pill), `app_shadows.dart` (soft).
- `app_theme.dart` — aydınlık M3 ThemeData (mevcut `buildFeedbackTheme` yerine/yeni).
- **Paylaşık component'lar** `lib/design_system/components/` (veya `widgets/ui/`):
  `PrimaryButton` (gradient), `SecondaryButton`, `AppCard`, `AppTextField`, `Chip/Pill`, `ReactionCard`,
  `StarRating`, `StatTile`, `SectionHeader`, `AppAppBar`, `AppBottomNav`, `EmptyState`, `ErrorState`,
  `LoadingSkeleton`, `SuccessAnimation`, `SentimentDonut`.

## R. Değiştirilmesi gereken mevcut dosyalar (görsel)

- **`lib/main.dart`** — tüm ekranlar + ana-ekran kartları (en büyük iş; ekran-ekran fazlanır).
- `lib/screens/settings_screen.dart`, `lib/screens/premium_screen.dart`.
- `lib/widgets/app_onboarding.dart`, `community_feedback_view.dart`, `simple_request_summary_view.dart`,
  `audience_score_widgets.dart`, `link_validity_countdown.dart`, `link_plan_banner.dart`, `feedback_link_tile.dart`.
- `lib/theme/app_theme.dart` + `lib/theme/feedback_material_theme.dart` — **yeni design-system ile değişir/yenilenir.**
- `lib/l10n/app_localizations.dart` — yeni metin anahtarları (TR+EN) eklenir.
- **Dokunulmayacak (mantık/backend):** `services/*` (firestore, railway, auth, iap, report, openai,
  reaction, rating, community/simple store, app_data_backend), `models/*`, `config/{backend_config,iap_products,
  feedback_reactions,feature_flags}`, `firebase_options.dart`, `firestore.rules`, `functions/`. Bunların
  **çağrıları** korunur; yalnızca onları kullanan UI değişir.

## S. Database / backend değişikliği gerekli mi?

**HAYIR (beklenen sonuç doğrulandı).**
- Tüm mockup verisi mevcut Firestore'dan türetilebilir: linkler (`links`), yorumlar (`feedbacks`), topluluk
  özeti (`CommunityFeedbackSummary`), profil (`users`).
- Yeni koleksiyon/şema, yeni backend, auth rewrite, Firestore redesign **gerekmez**.
- **İstisnalar (backend eklenmez, UI'da uyarlanır):**
  - **Abonelik (mockup C-15):** eklenmez — kredi modeli korunur, fiyat IAP'den.
  - **Bildirimler (mockup C-14):** altyapı yok — satır gizlenir/placeholder; sistem kurulmaz.
  - **Profil istatistik + Link Geçmişi (mockup C-13):** yeni şema yok; mevcut `linksForOwnerStream` + feedback
    sayım/skorlarından **toplama sorgusuyla** türetilir. Türetilemeyen metrik gösterilmez.

---

## Özet & öneri

- **S = HAYIR** — backend/DB'ye dokunmadan tam görsel yeniden tasarım mümkün.
- **En büyük iş:** (1) aydınlık **design-system** + paylaşık component'lar (Q), (2) **`main.dart` monolitinin**
  ekran-ekran görsel refactor'ü (P1), (3) koyu→aydınlık **tema/renk token** geçişinde görünmezlik riskinin
  yönetimi (P2).
- **Sıra (prompt 40):** Design System → Shared Components → Splash/Onboarding → Guest Home/Login → Logged Home →
  Create Link → Link Created → Active Dashboard → Feedback akışı → Success → AI Summary → Real Comments →
  Profile → Settings → Premium → Responsive Web → Polish. Her faz sonunda `flutter analyze` + davranış doğrulama +
  regresyon (prompt 41–42).
- **Değişmez ilke:** iş mantığı, backend, Firestore, auth, IAP, reaction/rating/AI sözleşmeleri KORUNUR;
  yalnızca sunum katmanı yenilenir.
