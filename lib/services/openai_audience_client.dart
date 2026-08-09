import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/community_feedback_summary.dart';
import '../models/creator_intelligence_report.dart';
import '../models/feedback_entry.dart';

/// Yorum özetleme / kümeleme (topluluk özeti).
///
/// P0.1 — AI YALNIZCA sunucu-tarafı proxy üzerinden çağrılır; OpenAI anahtarı
/// İSTEMCİDE TUTULMAZ (anahtarı sunucu ekler). İstemcide doğrudan OpenAI çağrısı
/// veya gömülü anahtar YOKTUR. Proxy ayarlı değilse AI kapalı sayılır ve
/// çağıranlar sezgisel yedeğe düşer (uygulama kırılmaz).
///
/// Yapılandırma: `--dart-define=AI_PROXY_URL=https://<host>/ai/chat`
class OpenAiAudienceClient {
  OpenAiAudienceClient();

  static const _model = 'gpt-4o-mini';

  /// Sunucu-tarafı AI proxy (Railway `/ai/chat`). AI'nın tek çıkış noktası.
  static const _aiProxyUrl = String.fromEnvironment('AI_PROXY_URL', defaultValue: '');

  String get _endpoint => _aiProxyUrl;

  static const int chunkSize = 90;

  /// AI yalnızca proxy ayarlıysa kullanılabilir (istemcide anahtar yok).
  bool get isConfigured => _aiProxyUrl.isNotEmpty;

  static String _systemChunkPartial(bool outputEnglish) => outputEnglish
      ? '''
You are a brutally honest social-media analyst. You receive ONE chunk of real follower comments.
Each line: mood|relationship|survey_json|text.

CRITICAL RULES:
1. READ EVERY COMMENT CAREFULLY. Do not generalize — extract exactly what each person said.
2. If a comment is clearly negative/hostile (insults, accusations, "you are a liar"), flag it honestly in "riskler". Do NOT soften or reframe hostility.
3. Separate genuine praise from polite/neutral comments. "Good" is not the same as "Your tutorials changed how I work".
4. For "spesifikTavsiyeler": extract any concrete suggestions about WHAT the creator should post, share, or change. Quote the commenter's actual words/ideas.
5. If comments mention specific content types (e.g. "make more tutorials", "do Q&A", "share behind-the-scenes"), capture them verbatim.
6. If the survey JSON has platform, frequency, content focus suggestions, or 1–5 scores, integrate them into highlights.
7. If text mentions audio, video, edit, lighting, cover, thumbnail, shoot, put into "uretimVeGorselNotlar".

OUTPUT SCHEMA (no other text):
{"partOzeti":"3-6 sentences; honest summary of what commenters ACTUALLY said — quote key phrases","vurgular":["specific positive points with evidence from comments"],"riskler":["specific negative signals — quote hostile/critical phrases honestly"],"spesifikTavsiyeler":["concrete content/growth suggestions extracted from comments"],"uretimVeGorselNotlar":"technical/visual notes from this chunk or empty string"}
'''
      : '''
Sen acımasızca dürüst bir sosyal medya analistisin. Sana TEK BİR PARÇA gerçek takipçi yorumu verilecek.
Her satır: mood|ilişki|anket_json|metin.

KRİTİK KURALLAR:
1. HER YORUMU DİKKATLE OKU. Genelleme yapma — her kişinin ne dediğini tam olarak çıkar.
2. Yorum açıkça olumsuz/saldırgansa (hakaret, suçlama, "yalancısın", "dolandırıcı") bunu "riskler"de DÜRÜSTÇE yaz. Düşmanlığı yumuşatma veya çerçeveleme.
3. Gerçek övgüyü kibar/nötr yorumlardan ayır. "İyi" ile "Senin sayende hayatım değişti" aynı şey değil.
4. "spesifikTavsiyeler" için: İçerik üreticisinin NE paylaşması, NE yapması veya NE değiştirmesi gerektiğine dair somut önerileri çıkar. Yorumcunun gerçek kelimelerini/fikirlerini kullan.
5. Yorumlarda spesifik içerik türleri geçiyorsa ("daha fazla tutorial yap", "Q&A yap", "sahne arkası paylaş") bunları aynen al.
6. Anket alanında platform, sıklık, içerik türü önerisi ve 1-5 puanlar varsa mutlaka özetle ve vurgularda kullan.
7. Metinlerde ses, görüntü, kurgu, ışık, kapak, thumbnail, çekim, montaj geçiyorsa bunları "uretimVeGorselNotlar"a al.

ÇIKTI ŞEMASI (başka metin yok):
{"partOzeti":"3-6 cümle; yorumcuların GERÇEKTE ne dediğinin dürüst özeti — kilit ifadeleri alıntıla","vurgular":["yorumlardan kanıtla desteklenen spesifik olumlu noktalar"],"riskler":["spesifik olumsuz sinyaller — düşmanca/eleştirel ifadeleri dürüstçe alıntıla"],"spesifikTavsiyeler":["yorumlardan çıkarılan somut içerik/büyüme önerileri"],"uretimVeGorselNotlar":"ses/görüntü/kurgu/kapak ile ilgili bu parçadan çıkan kısa özet (yoksa boş string)"}
''';

  /// Ham yorumları parçalayıp her parça için kısa JSON özet biriktirir (birleştirme için).
  Future<String?> collectPartialsDigest(
    List<FeedbackEntry> entries, {
    void Function(int index1Based, int totalChunks)? onChunkProgress,
    bool outputEnglishModel = false,
  }) async {
    if (!isConfigured || entries.isEmpty) return null;

    final chunks = <List<FeedbackEntry>>[];
    for (var i = 0; i < entries.length; i += chunkSize) {
      chunks.add(entries.sublist(i, i + chunkSize > entries.length ? entries.length : i + chunkSize));
    }

    final systemChunk = _systemChunkPartial(outputEnglishModel);

    final buf = StringBuffer();
    for (var p = 0; p < chunks.length; p++) {
      onChunkProgress?.call(p + 1, chunks.length);
      final userChunk = outputEnglishModel
          ? '''
CHUNK ${p + 1}/${chunks.length} — line format: mood|relationship|survey_json|text
survey_json: creator-context JSON or "-" (none). May include familiarity, platforms, watchFrequency, contentFocus, scoreProduction–scoreConsistency.
mood: 1 positive, 0 neutral, -1 negative

${_encodeLines(chunks[p])}
'''
          : '''
PARÇA ${p + 1}/${chunks.length} — satır formatı: mood|ilişki|anket_json|metin
anket_json: içerik üreticisi bağlamı (JSON) veya "-" (yok). İçinde: familiarity, platforms, watchFrequency, contentFocus (izleyicinin “hangi türde daha iyi olabilir” önerisi), scoreProduction–scoreConsistency olabilir.
mood: 1 olumlu, 0 nötr, -1 olumsuz

${_encodeLines(chunks[p])}
''';
      final raw = await _chat(
        system: systemChunk,
        user: userChunk,
        jsonMode: true,
        maxTokens: 1200,
      );
      if (raw == null) return null;
      buf.writeln(
        outputEnglishModel
            ? '--- CHUNK ${p + 1} / ${chunks.length} ---'
            : '--- PARÇA ${p + 1} / ${chunks.length} ---',
      );
      buf.writeln(raw);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return buf.toString();
  }

  /// Heuristik rapor JSON'unu premium danışman dilinde yeniden yazar; sayıları şema korur.
  Future<CreatorIntelligenceReport?> refineCreatorIntelligence(
    CreatorIntelligenceReport heuristic, {
    String? partialsDigest,
    String? surveyAggregateBlock,
    bool outputEnglishModel = false,
  }) async {
    if (!isConfigured) return null;

    final system = outputEnglishModel
        ? '''
You are a brutally honest content strategist and growth consultant. Task: keep all numeric fields and schema keys EXACTLY as in the input JSON, but rewrite TEXT fields based on what commenters ACTUALLY said.

CRITICAL APPROACH:
- DO NOT produce generic advice. Every recommendation must reference specific phrases, complaints, or suggestions from the chunk digests.
- If comments contain insults or accusations, acknowledge them honestly — do not sanitize.
- If there is only 1 comment, say so and note that conclusions are limited.
- Give SPECIFIC growth suggestions: "Your followers asked for X — share that to grow", "Comments suggest posting more Y format".

TEXT QUALITY:
- executiveSummary: At least 2 paragraphs. Quote or paraphrase actual comments. State what commenters literally said — praise AND criticism. If survey exists, mention.
- strategicDigest: Use "▸" sections. Each section must cite real comment evidence. Include a "▸ Specific growth actions" section with content ideas directly derived from what commenters requested or implied.
- visualAndFormatInsight: Based on actual technical mentions in comments. If nobody mentioned visuals, say "No visual feedback from commenters." Don't invent feedback.
- comprehensiveCoachLetter: Address creator directly ("you"). Be motivating but HONEST. If feedback is harsh, acknowledge it. Synthesize real quotes. Give specific next steps like "Based on comment X, try posting Y".
- topDiagnoses: Each diagnosis must reference what comments actually said, not generic themes.
- actionPlan: Every action must be derived from real comment patterns. Example: "3 commenters asked for tutorials — create a weekly tutorial series".
- segments: Describe actual audience behavior observed in comments, not theoretical segments.
- riskOpportunity: Quote actual risks from comments; opportunities based on real requests.

DO NOT CHANGE:
- cover.communityPerception, trust, contentClarity, subScores
- heatMap percentages and hint counts
- themeSignalTotal, uniqueCommentCount
- contentRecipe percent numbers
Output: a single JSON object; no markdown fences.
'''
        : '''
Sen acımasızca dürüst bir içerik stratejisti ve büyüme danışmanısın. Görevin: verilen JSON nesnesindeki
sayıları, yüzdeleri ve şema alan adlarını AYNEN KORUYARAK yalnızca METİN alanlarını yorumcuların GERÇEKTE
ne dediğine dayalı olarak yeniden yazmak.

KRİTİK YAKLAŞIM:
- Jenerik tavsiye ÜRETME. Her öneri, parça özetlerindeki gerçek ifadelere, şikayetlere veya önerilere atıfta bulunmalı.
- Yorumlar hakaret veya suçlama içeriyorsa bunu DÜRÜSTÇE kabul et — temizleme/yumuşatma yapma.
- Sadece 1 yorum varsa bunu belirt ve sonuçların sınırlı olduğunu not düş.
- SPESİFİK büyüme önerileri ver: "Takipçilerin X istemiş — bunu paylaşarak büyüyebilirsin", "Yorumlar Y formatında daha fazla içerik önerir".

ZORUNLU METİN KALİTESİ:
- executiveSummary: En az 2 paragraf. Gerçek yorumları alıntıla veya özetle. Yorumcuların birebir ne dediğini yaz — övgü VE eleştiri. Anket varsa değin.
- strategicDigest: "▸" ile bölümler. Her bölüm gerçek yorum kanıtı göstermeli. "▸ Spesifik büyüme aksiyonları" bölümü ekle: yorumcuların istediği veya ima ettiği içerik fikirlerini doğrudan buraya yaz.
- visualAndFormatInsight: Yorumlardaki gerçek teknik bahislere dayalı. Kimse görselden bahsetmediyse "Yorumculardan görsel geri bildirim gelmedi" yaz. Uydurma yapma.
- comprehensiveCoachLetter: İçerik üreticisine doğrudan hitap ("sen"). Motive edici ama DÜRÜST ol. Geri bildirim sertteyse bunu kabul et. Gerçek alıntıları sentezle. "X yorumuna göre Y paylaşmayı dene" gibi spesifik adımlar ver.
- topDiagnoses: Her teşhis yorumların GERÇEKTE ne dediğine atıf yapmalı, jenerik tema değil.
- actionPlan: Her aksiyon gerçek yorum örüntülerinden türetilmeli. Örnek: "3 yorumcu tutorial istemiş — haftalık tutorial serisi başlat".
- segments: Yorumlarda gözlemlenen gerçek kitle davranışını tanımla, teorik segmentler değil.
- riskOpportunity: Yorumlardan gerçek riskleri alıntıla; fırsatlar gerçek isteklere dayalı olsun.

KORU (dokunma):
- cover.communityPerception, trust, contentClarity, subScores
- heatMap tüm yüzdeleri ve hint sayıları
- themeSignalTotal, uniqueCommentCount
- contentRecipe içindeki percent sayıları
- Çıktı: TEK bir JSON nesnesi; ek açıklama veya markdown fence yok.
''';

    final user = outputEnglishModel
        ? '''
AGGREGATED SURVEY SUMMARY (all comments — do not change counts; use to enrich text):
${surveyAggregateBlock ?? '(No or minimal survey summary.)'}

---

CHUNK DIGESTS (JSON lines; uretimVeGorselNotlar holds visual/technical hints):
${partialsDigest ?? '(No chunk digest — refine heuristic text fields only.)'}

---

HEURISTIC REPORT (JSON — preserve schema and numbers; expand text per rules above):
${jsonEncode(heuristic.toJson())}
'''
        : '''
TOPLU YAPISAL ANKET ÖZETİ (tüm yorumlar — sayıları değiştirme; metinleri bununla zenginleştir):
${surveyAggregateBlock ?? '(Anket özeti yok veya çok az.)'}

---

PARÇA ÖZETLERİ (JSON satırları; uretimVeGorselNotlar alanları görsel/teknik ipuçları içerir):
${partialsDigest ?? '(Parça özeti yok — sadece heuristik JSON metinlerini iyileştir.)'}

---

HEURİSTİK RAPOR (JSON — şemayı ve sayıları koru; metin alanlarını yukarıdaki kurallarla genişlet):
${jsonEncode(heuristic.toJson())}
''';

    final raw = await _chat(
      system: system,
      user: user,
      jsonMode: true,
      maxTokens: 9000,
    );
    if (raw == null) return null;
    final map = _parseJsonObject(raw);
    if (map == null) return null;
    try {
      return CreatorIntelligenceReport.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Basit geri bildirim için üst sınır: tek çağrıda gönderilecek yorum sayısı.
  /// Tek çağrıda gönderilecek yorum sayısı (parça).
  static const int _takeawayChunk = 60;
  /// İşlenecek üst sınır (en yeni N yorum) — maliyet/gecikme sınırı.
  static const int _maxComments = 300;
  /// Kümelemeye gönderilecek en fazla farklı etiket.
  static const int _maxClusterLabels = 160;

  /// Yorumlardan konuya-özel çıkarımları çıkarır; **eş anlamlıları KÜMELER** ve
  /// sayımı KOD yapar. Binlerce yorumda "her kişi tek tek" yerine tek "N kişi — …"
  /// satırı üretir: (1) parçalı çıkarım, (2) AI kümeleme, (3) canonical'e göre sayım.
  Future<List<AudienceRequest>> extractRequests(
    List<FeedbackEntry> entries, {
    bool outputEnglishModel = false,
  }) async {
    if (!isConfigured || entries.isEmpty) return const [];
    final sample = entries.length > _maxComments
        ? entries.sublist(0, _maxComments)
        : entries;

    final system = outputEnglishModel
        ? '''
You turn follower comments into SHORT, TOPIC-SPECIFIC takeaways. You receive numbered comments.
EVERY meaningful comment must produce at least one takeaway — a REQUEST or an OBSERVATION.

MOST IMPORTANT RULE: Each takeaway must name the SPECIFIC SUBJECT the comment is about.
Generic labels are BANNED — never write vague things like "likes your content" or "raises criticism".
Name the actual subject: "Loves your hair", "Loves your food videos — wants more", "Criticizes your audio",
"Wants more vlogs", "Loves your smile", "Finds your editing too fast".

RULES:
1. REQUEST (explicit/implied): short imperative + subject — "Post shorter videos", "Improve audio quality".
2. OBSERVATION (praise/criticism/opinion): subject + view — "Loves your hair", "Finds your delivery confusing".
3. Label = 2–8 words; reflect the comment's REAL topic (take the actual subject/theme mentioned).
4. Merge takeaways that mean the same thing into ONE label; reuse a fitting label.
5. If one comment carries several takeaways, add a separate item for each.
6. Skip ONLY empty/spam/meaningless comments.
7. Do NOT count; each item = one takeaway from one comment.

OUTPUT (a single JSON object, no other text):
{"items":[{"label":"Loves your food videos — wants more","quote":"short quote"}]}
'''
        : '''
Sen takipçi yorumlarını KISA ama KONUYA ÖZEL çıkarımlara çeviren bir analistsin. Sana numaralı yorumlar verilecek.
HER anlamlı yorum en az bir çıkarım üretmeli — bir İSTEK ya da bir GÖZLEM.

EN ÖNEMLİ KURAL: Her çıkarım, yorumun HANGİ KONUYA dair olduğunu SOMUT belirtmeli.
Jenerik etiket YASAK — "içeriğini beğeniyor", "eleştiri belirtiyor" gibi belirsiz ifadeler ASLA yazma.
Konuyu adlandır: "Saçını beğeniyor", "Yemek videolarını çok seviyor — devamını istiyor", "Ses kalitesini eleştiriyor",
"Daha çok vlog istiyor", "Gülüşünü beğeniyor", "Kurguyu çok hızlı buluyor".

KURALLAR:
1. İSTEK (açık/ima): kısa emir + konu — "Daha kısa video çek", "Ses kalitesini artır".
2. GÖZLEM (övgü/eleştiri/görüş): konu + görüş — "Saçını beğeniyor", "Anlatımını karışık buluyor".
3. Etiket = 2–8 kelime; yorumun GERÇEK konusunu yansıt (yorumdaki asıl özneyi/temayı al).
4. Aynı anlama gelen çıkarımları TEK etiketle birleştir; uygun etiketi tekrar kullan.
5. Bir yorumda birden çok çıkarım varsa her biri için ayrı öğe ekle.
6. YALNIZCA boş/spam/anlamsız yorumları atla.
7. Sayma YAPMA; her öğe = bir yorumdaki bir çıkarım.

ÇIKTI (tek bir JSON nesnesi, başka metin yok):
{"items":[{"label":"Yemek videolarını çok seviyor — devamını istiyor","quote":"kısa alıntı"}]}
''';

    // 1) Parçalı çıkarım: her yorumdan {label, quote}. Ölçeklenir (parça parça).
    final raw = <({String label, String quote})>[];
    for (var start = 0; start < sample.length; start += _takeawayChunk) {
      final end = (start + _takeawayChunk) < sample.length
          ? (start + _takeawayChunk)
          : sample.length;
      final chunk = sample.sublist(start, end);
      final buf = StringBuffer();
      for (var j = 0; j < chunk.length; j++) {
        var t = chunk[j].textRaw.replaceAll('\n', ' ').trim();
        if (t.isEmpty) continue;
        if (t.length > 300) t = '${t.substring(0, 300)}…';
        final s = chunk[j].creatorSurvey;
        final survey = (s != null && !s.isEffectivelyEmpty)
            ? ' [anket: ${s.toCompactJson()}]'
            : '';
        buf.writeln('${j + 1}) $t$survey');
      }
      final user = outputEnglishModel
          ? 'COMMENTS:\n${buf.toString()}'
          : 'YORUMLAR:\n${buf.toString()}';
      final resp = await _chat(
        system: system,
        user: user,
        jsonMode: true,
        maxTokens: 2000,
      );
      if (resp == null) continue;
      final map = _parseJsonObject(resp);
      final items = map?['items'];
      if (items is! List) continue;
      for (final it in items) {
        if (it is! Map) continue;
        final label = (it['label'] ?? '').toString().trim();
        if (label.isEmpty) continue;
        final quote = (it['quote'] ?? '').toString().trim();
        raw.add((label: label, quote: quote));
      }
    }
    if (raw.isEmpty) return const [];

    // 2) Kümeleme: eş anlamlı etiketleri tek canonical'e indir (tek tek satır olmasın).
    final distinct = <String>{for (final r in raw) r.label}.toList();
    final canonical = await _clusterLabels(distinct, outputEnglishModel);
    String canon(String label) => canonical[label.toLowerCase()] ?? label;

    // 3) Sayımı KOD yapar: canonical etikete göre grupla + gerçek yorum alıntısı topla.
    final groups = <String, ({String label, int count, List<String> examples})>{};
    for (final r in raw) {
      final c = canon(r.label);
      final key = c.toLowerCase();
      final g = groups[key];
      if (g == null) {
        groups[key] = (
          label: c,
          count: 1,
          examples: r.quote.isEmpty ? <String>[] : <String>[r.quote],
        );
      } else {
        if (r.quote.isNotEmpty &&
            g.examples.length < 2 &&
            !g.examples.contains(r.quote)) {
          g.examples.add(r.quote);
        }
        groups[key] = (label: g.label, count: g.count + 1, examples: g.examples);
      }
    }

    final list = groups.values
        .map((g) => AudienceRequest(label: g.label, count: g.count, examples: g.examples))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  /// Eş anlamlı çıkarım etiketlerini tek "canonical" etikete indiren AI kümelemesi.
  /// Dönüş: her (küçük harf) etiket → temsili etiket eşlemesi.
  Future<Map<String, String>> _clusterLabels(
    List<String> labels,
    bool english,
  ) async {
    if (labels.length <= 1) return const {};
    final capped = labels.length > _maxClusterLabels
        ? labels.sublist(0, _maxClusterLabels)
        : labels;
    final system = english
        ? 'Merge ONLY labels about the SAME specific subject with the same opinion. '
            'NEVER merge different subjects. The canonical label MUST name the subject; '
            'generic labels like "Praise", "Criticism", "Suggestion" are BANNED. '
            'Example: "Suggests dyeing your hair" + "Says dyed hair would look good" '
            '→ canonical "Suggests you dye your hair". But "Praises your success" and '
            '"Likes your food content" are DIFFERENT subjects → keep them separate. '
            'Every label appears in exactly one group; a unique label is its own group. '
            'Output a single JSON object only: '
            '{"clusters":[{"canonical":"...","members":["...","..."]}]}'
        : 'Sadece AYNI SPESİFİK KONU ve aynı görüşü ifade eden etiketleri tek gruba birleştir. '
            'FARKLI konuları ASLA birleştirme. Canonical etiket KONUYU içermeli; '
            '"Övgü", "Eleştiri", "Öneri" gibi GENEL etiket YASAK. '
            'Örnek: "Saçını boyatmasını öneriyor" + "Saçını boyamasını öneriyor" '
            '→ canonical "Saçını boyatmanı öneriyor". Ama "Başarılarını övüyor" ile '
            '"Yemek içeriklerini beğeniyor" FARKLI konu → ayrı kalır. '
            'Her etiket tam olarak bir grupta; tekil etiket kendi grubudur. '
            'Yalnızca tek bir JSON nesnesi döndür: '
            '{"clusters":[{"canonical":"...","members":["...","..."]}]}';
    final user = (english ? 'LABELS:\n' : 'ETİKETLER:\n') +
        capped.map((l) => '- $l').join('\n');
    final resp = await _chat(
      system: system,
      user: user,
      jsonMode: true,
      maxTokens: 3000,
    );
    if (resp == null) return const {};
    final map = _parseJsonObject(resp);
    final clusters = map?['clusters'];
    if (clusters is! List) return const {};
    final out = <String, String>{};
    for (final c in clusters) {
      if (c is! Map) continue;
      final canonicalLabel = (c['canonical'] ?? '').toString().trim();
      if (canonicalLabel.isEmpty) continue;
      out[canonicalLabel.toLowerCase()] = canonicalLabel;
      final members = c['members'];
      if (members is List) {
        for (final m in members) {
          final ms = m.toString().trim();
          if (ms.isNotEmpty) out[ms.toLowerCase()] = canonicalLabel;
        }
      }
    }
    return out;
  }

  /// FeedbackToMe 2.0 — Topluluk özeti.
  ///
  /// AI'ye YAPILANDIRILMIŞ GERÇEK VERİ verilir (kümelenmiş istekler + sayılar +
  /// örnek yorumlar). AI YALNIZCA sıcak metin alanlarını (mood/headline/
  /// mostLiked/mostMentioned/mixedOpinions/hotTake/shortSummary/confidence)
  /// yazar; içerik hakkında BAĞIMSIZ/teknik değerlendirme ÜRETMEZ.
  ///
  /// Meta alanları (crowdScore, sayımlar, reaction dağılımı, realComments)
  /// çağıran tarafından koddan doldurulur. AI başarısızsa `null` döner.
  Future<CommunityFeedbackSummary?> summarizeCommunity({
    required List<AudienceRequest> requests,
    required int feedbackCount,
    required int positive,
    required int neutral,
    required int negative,
    Map<String, int> reactionCounts = const {},
    double? crowdScore,
    List<String> sampleComments = const [],
    bool outputEnglishModel = false,
  }) async {
    if (!isConfigured || feedbackCount <= 0) return null;

    // Yapılandırılmış girdi: kümelenmiş istekler (sayı+örnek) + duygu + örnek yorumlar.
    final buf = StringBuffer();
    buf.writeln(
        '${english(outputEnglishModel, 'FEEDBACK COUNT', 'YORUM SAYISI')}: $feedbackCount');
    buf.writeln(
        '${english(outputEnglishModel, 'SENTIMENT', 'DUYGU')}: +$positive / =$neutral / -$negative');
    if (reactionCounts.isNotEmpty) {
      final rc = reactionCounts.entries.map((e) => '${e.key}:${e.value}').join(' ');
      buf.writeln(
          '${english(outputEnglishModel, 'REACTIONS', 'REAKSİYONLAR')}: $rc');
    }
    if (crowdScore != null) {
      buf.writeln(
          '${english(outputEnglishModel, 'CROWD SCORE', 'TOPLULUK SKORU')}: ${crowdScore.toStringAsFixed(1)}/10');
    }
    if (requests.isNotEmpty) {
      buf.writeln();
      buf.writeln(english(outputEnglishModel,
          'CLUSTERED TOPICS (how many people, with a real quote):',
          'GRUPLANMIŞ KONULAR (kaç kişi söyledi, gerçek alıntıyla):'));
      for (final r in requests.take(24)) {
        final ex = r.examples.isNotEmpty ? ' — "${r.examples.first}"' : '';
        buf.writeln('- ${r.label} (${r.count})$ex');
      }
    }
    if (sampleComments.isNotEmpty) {
      buf.writeln();
      buf.writeln(english(outputEnglishModel,
          'SAMPLE REAL COMMENTS (verbatim):', 'ÖRNEK GERÇEK YORUMLAR (birebir):'));
      for (final c in sampleComments.take(12)) {
        var t = c.replaceAll('\n', ' ').trim();
        if (t.isEmpty) continue;
        if (t.length > 240) t = '${t.substring(0, 240)}…';
        buf.writeln('- $t');
      }
    }

    final system = outputEnglishModel
        ? '''
You turn REAL community feedback into a SHORT, SOCIAL, FUN summary for the content owner.
You are NOT a design critic, UX consultant or technical evaluator.

HARD RULES:
1. NEVER judge the content on your own. You did not see it. Only interpret the feedback provided.
2. Use ONLY the real feedback given. Do not invent problems nobody mentioned.
3. No technical/UX/design jargon. No academic or corporate report tone.
4. Keep it short, warm, natural — like a friend texting.
5. Do not distort the feedback. Do not exaggerate.
6. With few comments, avoid firm verdicts. Say things like "a few people seem unsure".
7. Never generalize from a single negative comment.
8. If opinions clearly split, say so in mixedOpinions ("the crowd is a bit divided").
9. hotTake MUST be a real comment quoted from the input (pick a striking/funny one), or "".
10. mostLiked / mostMentioned come from the clustered topics — name the actual subject.
11. confidence: "low" for few/thin feedback, "high" only with clear, plentiful signal.

OUTPUT (a single JSON object, no other text):
{"overallMood":"positive|mixed|neutral|negative","headline":"...","mostLiked":["..."],"mostMentioned":["..."],"mixedOpinions":["..."],"hotTake":"...","shortSummary":"...","confidence":"low|medium|high"}
'''
        : '''
Sen GERÇEK topluluk geri bildirimini KISA, SOSYAL ve EĞLENCELİ bir özete çeviren birisin.
Tasarım eleştirmeni, UX danışmanı ya da teknik değerlendirici DEĞİLSİN.

KATI KURALLAR:
1. İçeriği ASLA kendi başına değerlendirme. Onu görmedin. Yalnızca verilen geri bildirimi yorumla.
2. YALNIZCA verilen gerçek geri bildirimi kullan. Kimsenin söylemediği sorun UYDURMA.
3. Teknik/UX/tasarım jargonu YOK. Akademik veya kurumsal rapor dili YOK.
4. Kısa, sıcak, doğal tut — bir arkadaşın mesaj atması gibi.
5. Geri bildirimi çarpıtma, abartma.
6. Az yorum varsa kesin yargı kullanma. "Birkaç kişi kararsız görünüyor" gibi söyle.
7. Tek bir olumsuz yorumdan ASLA genelleme yapma.
8. Görüşler açıkça ikiye bölündüyse bunu mixedOpinions'ta belirt ("topluluk biraz ikiye bölünmüş").
9. hotTake, girdideki GERÇEK bir yorumdan alıntı OLMALI (çarpıcı/eğlenceli olanı seç) ya da "".
10. mostLiked / mostMentioned gruplanmış konulardan gelir — asıl konuyu adlandır.
11. confidence: az/zayıf veride "low", yalnızca net ve bol sinyalde "high".

ÇIKTI (tek bir JSON nesnesi, başka metin yok):
{"overallMood":"positive|mixed|neutral|negative","headline":"...","mostLiked":["..."],"mostMentioned":["..."],"mixedOpinions":["..."],"hotTake":"...","shortSummary":"...","confidence":"low|medium|high"}
''';

    final user =
        (outputEnglishModel ? 'COMMUNITY FEEDBACK DATA:\n' : 'TOPLULUK GERİ BİLDİRİM VERİSİ:\n') +
            buf.toString();

    final resp = await _chat(
      system: system,
      user: user,
      jsonMode: true,
      maxTokens: 900,
    );
    if (resp == null) return null;
    final map = _parseJsonObject(resp);
    if (map == null) return null;

    List<String> strList(dynamic v) => (v is List)
        ? v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : const [];

    return CommunityFeedbackSummary(
      mood: communityMoodFromString(map['overallMood']?.toString()),
      headline: map['headline']?.toString().trim() ?? '',
      mostLiked: strList(map['mostLiked']),
      mostMentioned: strList(map['mostMentioned']),
      mixedOpinions: strList(map['mixedOpinions']),
      hotTake: map['hotTake']?.toString().trim() ?? '',
      shortSummary: map['shortSummary']?.toString().trim() ?? '',
      confidence: summaryConfidenceFromString(map['confidence']?.toString()),
      crowdScore: crowdScore,
      feedbackCount: feedbackCount,
      positive: positive,
      neutral: neutral,
      negative: negative,
      reactionCounts: reactionCounts,
      realComments: sampleComments
          .map((c) => c.replaceAll('\n', ' ').trim())
          .where((c) => c.isNotEmpty)
          .take(6)
          .toList(),
      aiUsed: true,
    );
  }

  /// Küçük dil yardımcıları (EN/TR seçimi).
  static String english(bool en, String a, String b) => en ? a : b;

  String _encodeLines(List<FeedbackEntry> chunk) {
    final buf = StringBuffer();
    for (final e in chunk) {
      var mm = e.mood ?? 0;
      if (mm > 1) mm = 1;
      if (mm < -1) mm = -1;
      final r = (e.relation ?? '-').replaceAll('|', ' ').trim();
      final meta = (e.creatorSurvey != null && !e.creatorSurvey!.isEffectivelyEmpty)
          ? e.creatorSurvey!.toCompactJson()
          : '-';
      var t = e.textRaw.replaceAll('\n', ' ').trim();
      t = t.replaceAll('|', '¦');
      if (t.length > 420) t = '${t.substring(0, 420)}…';
      buf.writeln('$mm|$r|$meta|$t');
    }
    return buf.toString();
  }

  Future<String?> _chat({
    required String system,
    required String user,
    required bool jsonMode,
    int maxTokens = 2000,
  }) async {
    // AI yalnızca sunucu proxy'si üzerinden; anahtar istemcide yok.
    if (_aiProxyUrl.isEmpty) return null;
    try {
      final body = <String, dynamic>{
        'model': _model,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
        'temperature': 0.28,
        'max_tokens': maxTokens,
        if (jsonMode) 'response_format': {'type': 'json_object'},
      };

      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final content = data['choices']?[0]?['message']?['content'] as String?;
      return content?.trim();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseJsonObject(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      final fence = s.lastIndexOf('```');
      if (fence != -1) s = s.substring(0, fence);
    }
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
