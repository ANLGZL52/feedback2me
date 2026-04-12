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
You are a senior social-media and creator-communication strategist (global audience).
You receive ONE chunk of comment lines. Each line: mood|relationship|survey_json|text.
If the survey JSON includes platform, frequency, suggested content types, and 1–5 scores, summarize it and use it in highlights.
If text mentions audio, video, edit, lighting, cover, thumbnail, shoot, or post-production, put that into "uretimVeGorselNotlar".
Video files are not analyzed—only viewer text and survey data.
Return compact JSON for this chunk only.
OUTPUT SCHEMA (no other text):
{"partOzeti":"2-5 sentences in English","vurgular":["bullet"],"riskler":["short if any"],"uretimVeGorselNotlar":"short technical/visual note from this chunk or empty string"}
'''
      : '''
Sen Türkiye pazarında çalışan kıdemli bir sosyal medya ve içerik üreticisi iletişimi uzmanısın.
Sana TEK BİR PARÇA yorum satırları verilecek. Her satır: mood|ilişki|anket_json|metin.
Anket alanında platform, sıklık, içerik türü önerisi ve 1-5 puanlar varsa mutlaka özetle ve vurgularda kullan.
Metinlerde ses, görüntü, kurgu, ışık, kapak, thumbnail, çekim, montaj geçiyorsa bunları "uretimVeGorselNotlar"a al.
Video dosyası analiz edilmiyor; sadece izleyici yazdığı metin ve anket var.
Sadece bu parça için kısa JSON döndür.
Çıktı ŞEMASI (başka metin yok):
{"partOzeti":"2-5 cümle","vurgular":["madde"],"riskler":["varsa kısa"],"uretimVeGorselNotlar":"ses/görüntü/kurgu/kapak ile ilgili bu parçadan çıkan kısa özet (yoksa boş string)"}
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
You are a senior content strategist and community consultant. Task: keep all numeric fields and schema keys EXACTLY as in the input JSON, but rewrite only TEXT fields in clear, warm, premium-advisory English.

TEXT QUALITY:
- executiveSummary: At least 2 paragraphs; sentiment + strongest theme + growth focus; if structured survey summary exists, mention in one sentence.
- strategicDigest: Long strategic brief; use "▸" sections (Perception, Platform/Format, Risk-Opportunity, 14-day experiment); merge production/visual notes from chunk digests.
- visualAndFormatInsight: TEXT only — visible content and format (thumbnail, first frame, light, framing, edit rhythm, audio/clarity, captions); combine survey production scores with technical phrases from comments. Gently note there is no pixel-level video analysis.
- comprehensiveCoachLetter: Directly address the creator ("you"); 4–8 paragraphs; motivating but honest closing; synthesize survey + comments + suggested formats; give a clear next step.
- themeRows[].meaning, segments, topDiagnoses, benchmarkLines, riskOpportunity: Reflect survey/chunk production-visual hints where possible.
- themeRows[].theme and other user-visible labels: use natural English.
- cover.oneLiner: One punchy sentence (do not change scores).

DO NOT CHANGE:
- cover.communityPerception, trust, contentClarity, subScores
- heatMap percentages and hint counts
- themeSignalTotal, uniqueCommentCount
- contentRecipe percent numbers
Output: a single JSON object; no markdown fences.
'''
        : '''
Sen kıdemli içerik stratejisti, görsel iletişim ve topluluk danışmanısın. Görevin: verilen JSON nesnesindeki
sayıları, yüzdeleri ve şema alan adlarını AYNEN KORUYARAK yalnızca METİN alanlarını Türkçe, sıcak ama net
teşhis diliyle, önceliklendirilmiş ve premium danışmanlık tonunda YENİDEN YAZMAK.

ZORUNLU METİN KALİTESİ:
- executiveSummary: En az 2 paragraf; duygu dağılımı + en güçlü tema + gelişim odağı; yapılandırılmış anket özeti varsa 1 cümleyle ona değin.
- strategicDigest: Uzun stratejik brifing; "▸" ile bölümler (Algı, Platform/Format, Risk-Fırsat, 14 günlük deney); parça özetlerindeki üretim/görsel notlarını burada birleştir.
- visualAndFormatInsight: SADECE METİN — görünür içerik ve format: kapak/thumbnail okunabilirliği, ilk kare, ışık, çerçeve, kurgu ritmi, ses/netlik, altyazı; izleyici anketindeki üretim puanları ile yorum metinlerindeki teknik ifadeleri birleştir. Video piksel analizi YOK olduğunu nazikçe belirt.
- comprehensiveCoachLetter: İçerik üreticisine doğrudan hitap ("sen"); 4–8 paragraf; motive edici ama dürüst kapanış mektubu; anket + yorum + önerilen içerik türlerini sentezle; net bir sonraki adım ver.
- themeRows[].meaning, segments, topDiagnoses, benchmarkLines, riskOpportunity: Anket ve parça özetlerindeki üretim/görsel ipuçlarını mümkün olduğunca yansıt.
- cover.oneLiner: Tek cümlede güçlü özet (sayıları değiştirmeden).

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
