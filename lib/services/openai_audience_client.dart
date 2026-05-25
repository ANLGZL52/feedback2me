import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/creator_intelligence_report.dart';
import '../models/feedback_entry.dart';

/// Parça özetleri + Creator Intelligence JSON iyileştirme.
/// API: `--dart-define=OPENAI_API_KEY=sk-...`
class OpenAiAudienceClient {
  OpenAiAudienceClient();

  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  static const _model = 'gpt-4o-mini';
  static const _url = 'https://api.openai.com/v1/chat/completions';

  static const int chunkSize = 90;

  bool get isConfigured => _apiKey.isNotEmpty;

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
            Uri.parse(_url),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
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
