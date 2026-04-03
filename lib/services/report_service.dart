import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../app_state.dart';
import '../models/audience_score.dart';
import '../models/creator_intelligence_report.dart';
import 'creator_intelligence_heuristic.dart';
import 'creator_survey_aggregate.dart';
import 'app_data_backend.dart';
import 'openai_audience_client.dart';

/// Rapor sonucu: tek link için toplanan yorumların analizi.
class ReportResult {
  ReportResult({
    required this.linkId,
    required this.feedbackCount,
    this.summary,
    this.themes,
    this.bullets,
    this.narrativeInsight,
    this.sentimentLine,
    this.prioritizedActions,
  });

  final String linkId;
  final int feedbackCount;
  final String? summary;
  final List<String>? themes;
  final List<String>? bullets;
  /// Yapay zeka tarzı çok cümleli özet (sosyal medya / iletişim odaklı).
  final String? narrativeInsight;
  /// "Olumlu / nötr / olumsuz" sayı veya yüzde satırı.
  final String? sentimentLine;
  /// Önceliklendirilmiş gelişim aksiyonları.
  final List<String>? prioritizedActions;
}

class AudienceAnalysisResult {
  AudienceAnalysisResult({
    required this.feedbackCount,
    required this.positiveCount,
    required this.neutralCount,
    required this.negativeCount,
    required this.scores,
    required this.intelligence,
    required this.summary,
    required this.themeBullets,
    required this.actionBullets,
    required this.relationBreakdown,
    required this.narrativeInsight,
    required this.strengths,
    required this.developmentAreas,
    required this.socialPersonalityGuidance,
  });

  final int feedbackCount;
  final int positiveCount;
  final int neutralCount;
  final int negativeCount;
  /// Sayısal puanlar (yorum dağılımı + hacim); gelişim grafiği ile ilişkili.
  final AudienceScoreBreakdown scores;
  /// Yapılandırılmış creator intelligence (UI kartları).
  final CreatorIntelligenceReport intelligence;
  final String summary;
  final List<String> themeBullets;
  final List<String> actionBullets;
  final List<String> relationBreakdown;
  /// Uzun paragraf: yorumların özeti ve yorum.
  final String narrativeInsight;
  /// Güçlü yönler (veriye dayalı maddeler).
  final List<String> strengths;
  /// Geliştirilmesi önerilen alanlar.
  final List<String> developmentAreas;
  /// Sosyal medya ve kişilik gelişimi için kapsamlı rehber maddeleri.
  final List<String> socialPersonalityGuidance;

  /// Firestore’a kayıtlı anlık görüntüden salt okuma ekranı.
  factory AudienceAnalysisResult.fromHistorySnapshot(AudienceScoreSnapshot s) {
    final intel = s.creatorReport ?? CreatorIntelligenceReport.empty();
    final summaryText = (s.executiveSummary != null && s.executiveSummary!.trim().isNotEmpty)
        ? s.executiveSummary!.trim()
        : intel.executiveSummary;
    final themeBullets = intel.themeRows.map((e) => '${e.theme} — ${e.meaning}').toList();
    final actionBullets = <String>[
      ...intel.actionPlan.quickWins7d.map((x) => '[7 gün] $x'),
      ...intel.actionPlan.medium30d.map((x) => '[30 gün] $x'),
      ...intel.actionPlan.brand60d.map((x) => '[60 gün] $x'),
    ];
    final narrativeInsight = (intel.strategicDigest != null && intel.strategicDigest!.trim().isNotEmpty)
        ? intel.strategicDigest!.trim()
        : '';
    final strengths = intel.benchmarkLines.isNotEmpty
        ? intel.benchmarkLines
        : (s.creatorReport == null
            ? const <String>[
                'Bu kayıt yalnızca skor içeriyor; yeni bir analiz tam raporu saklar.',
              ]
            : const <String>[]);
    final developmentAreas = intel.topDiagnoses.isNotEmpty
        ? intel.topDiagnoses.map((d) => '${d.title}: ${d.detail}').toList()
        : <String>[];
    final socialPersonalityGuidance = <String>[
      ...intel.segments.map((x) => '${x.segmentName} — ${x.action}'),
      ...intel.contentRecipe.map((c) => '%${c.percent} ${c.label}: ${c.detail}'),
      ...intel.replyTemplates.map((r) => 'Yanıt şablonu (${r.title}): ${r.text}'),
    ];
    return AudienceAnalysisResult(
      feedbackCount: s.feedbackCount,
      positiveCount: s.positiveCount,
      neutralCount: s.neutralCount,
      negativeCount: s.negativeCount,
      scores: s.scores,
      intelligence: intel,
      summary: summaryText,
      themeBullets: themeBullets,
      actionBullets: actionBullets,
      relationBreakdown: const [],
      narrativeInsight: narrativeInsight,
      strengths: strengths,
      developmentAreas: developmentAreas,
      socialPersonalityGuidance: socialPersonalityGuidance,
    );
  }
}

/// Takipçi analizi yükleme ekranı için aşama + metin.
enum AudienceAnalysisLoadPhase {
  fetchingComments,
  scanningComments,
  aiChunks,
  aiMerge,
  buildingHeuristicReport,
}

class AudienceAnalysisLoadState {
  const AudienceAnalysisLoadState({
    required this.phase,
    required this.title,
    this.subtitle,
    this.stepIndex,
    this.stepTotal,
  });

  final AudienceAnalysisLoadPhase phase;
  final String title;
  final String? subtitle;
  /// Örn. AI parça 3 / 34
  final int? stepIndex;
  final int? stepTotal;
}

/// Tema anahtar kelimeleri (Türkçe) — yorum metninde geçiş sıklığına göre puanlanır.
const Map<String, List<String>> _kThemeKeywords = {
  'İletişim ve netlik': [
    'anlaş',
    'net',
    'açık',
    'ifade',
    'düzgün',
    'karışık',
    'anlat',
    'dinle',
    'mesaj',
    'cümle',
    'konuş',
    'şeffaf',
  ],
  'Güven ve samimiyet': [
    'samimi',
    'güven',
    'doğal',
    'yapay',
    'inandırıcı',
    'samimiyetsiz',
    'dürüst',
    'çıkar',
    'maskeli',
    'otantik',
    'gerçek',
  ],
  'İçerik kalitesi': [
    'içerik',
    'faydalı',
    'değer',
    'boş',
    'bilgi',
    'yorum',
    'sıkıcı',
    'ilham',
    'özgün',
    'tekrar',
    'kalite',
    'fikir',
    'konu',
    'başlık',
  ],
  'Tutarlılık ve süreklilik': [
    'düzenli',
    'sık',
    'seyrek',
    'istikrar',
    'devam',
    'tutarlı',
    'ara ver',
    'sıklık',
    'program',
    'planlı',
  ],
  'Teknik ve sunum': [
    'ses',
    'görüntü',
    'kalite',
    'montaj',
    'kamera',
    'ışık',
    'kurgu',
    'altyazı',
    'mikrofon',
    'çözünürlük',
  ],
};

/// Sosyal medya / kişilik bağlamı (ek sinyal).
const List<String> _kSocialPersonalityHints = [
  'takipçi',
  'topluluk',
  'etkileşim',
  'beğeni',
  'paylaşım',
  'story',
  'reel',
  'shorts',
  'algoritma',
  'hashtag',
  'marka',
  'imaj',
  'kişilik',
  'karakter',
  'enerji',
  'pozitif',
  'negatif',
  'empati',
  'toksik',
  'sınır',
  'saygı',
  'motivasyon',
  'özgüven',
  'yorgun',
  'baskı',
  'stres',
];

class ReportService {
  ReportService({AppDataBackend? backend}) : _data = backend ?? appData;

  final AppDataBackend _data;

  int _moodBucket(int? mood) {
    if (mood == 1) return 1;
    if (mood == -1) return -1;
    return 0;
  }

  Future<ReportResult> generateReport(String linkId) async {
    final entries = await _data.getFeedbacksForLink(linkId);
    final count = entries.length;

    if (entries.isEmpty) {
      return ReportResult(
        linkId: linkId,
        feedbackCount: 0,
        summary: 'Henüz bu link için feedback yok.',
      );
    }

    int pos = 0, neu = 0, neg = 0;
    final themeScores = _emptyThemeScores();
    var socialHits = 0;

    for (final e in entries) {
      final m = _moodBucket(e.mood);
      if (m == 1) {
        pos++;
      } else if (m == -1) {
        neg++;
      } else {
        neu++;
      }
      _applyThemeScores(themeScores, e.textRaw, m);
      final t = e.textRaw.toLowerCase();
      for (final w in _kSocialPersonalityHints) {
        if (t.contains(w)) {
          socialHits++;
          break;
        }
      }
    }

    final total = count;
    final posPct = ((pos / total) * 100).round();
    final negPct = ((neg / total) * 100).round();
    final neuPct = ((neu / total) * 100).round();

    final sortedThemes = themeScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sortedThemes.first;
    final second = sortedThemes.length > 1 ? sortedThemes[1] : sortedThemes.first;

    final summary =
        'Bu link için $total yorum analiz edildi. Duygu dağılımı: %$posPct olumlu, '
        '%$neuPct nötr, %$negPct olumsuz. Öne çıkan başlıklar: "${top.key}" ve "${second.key}".';

    final narrativeInsight = _buildLinkNarrative(
      total: total,
      pos: pos,
      neu: neu,
      neg: neg,
      topTheme: top.key,
      secondTheme: second.key,
      socialHits: socialHits,
      themeScores: themeScores,
    );

    final prioritizedActions = _buildLinkActions(
      neg: neg,
      neu: neu,
      pos: pos,
      sortedThemes: sortedThemes,
    );

    final texts = entries.map((e) => e.textRaw).where((t) => t.isNotEmpty).toList();
    final bullets = texts
        .take(5)
        .map((t) => t.length > 100 ? '${t.substring(0, 100)}…' : t)
        .toList();

    final themesList = sortedThemes.map((e) => '${e.key}: ${e.value} eşleşme').toList();

    return ReportResult(
      linkId: linkId,
      feedbackCount: count,
      summary: summary,
      themes: themesList,
      bullets: bullets,
      narrativeInsight: narrativeInsight,
      sentimentLine: 'Olumlu: $pos • Nötr: $neu • Olumsuz: $neg',
      prioritizedActions: prioritizedActions,
    );
  }

  Future<AudienceAnalysisResult> generateAudienceAnalysis(
    String ownerId, {
    void Function(AudienceAnalysisLoadState state)? onLoadUpdate,
  }) async {
    onLoadUpdate?.call(
      const AudienceAnalysisLoadState(
        phase: AudienceAnalysisLoadPhase.fetchingComments,
        title: 'Yorum havuzu yükleniyor',
        subtitle: 'Sunucudan tüm geri bildirimler alınıyor…',
      ),
    );
    final entries = await _data.getAllFeedbacksForOwner(ownerId);
    if (entries.isEmpty) {
      return AudienceAnalysisResult(
        feedbackCount: 0,
        positiveCount: 0,
        neutralCount: 0,
        negativeCount: 0,
        summary:
            'Henüz yorum havuzunda veri yok. Analiz için linkini paylaşıp yorum toplamaya devam et.',
        themeBullets: const ['Yeterli veri oluştuğunda temalar burada listelenecek.'],
        actionBullets: const [
          'İlk hedef: en az 10–15 anlamlı yorum toplayarak örüntüleri güvenilir hale getir.',
        ],
        relationBreakdown: const [],
        narrativeInsight:
            'Yorum biriktiğinde; duygu dağılımı, temalar ve ilişki kırılımlarına göre '
            'sana özel bir özet ve gelişim önerileri burada oluşacak.',
        strengths: const [],
        developmentAreas: const ['Henüz değerlendirilecek yeterli geri bildirim yok.'],
        socialPersonalityGuidance: const [
          'Linkini hedef kitlenle (bio, hikâye, sabit yorum) paylaşarak örneklem çeşitliliğini artır.',
        ],
        scores: AudienceScoreBreakdown.zero,
        intelligence: CreatorIntelligenceReport.empty(),
      );
    }

    onLoadUpdate?.call(
      AudienceAnalysisLoadState(
        phase: AudienceAnalysisLoadPhase.scanningComments,
        title: '${entries.length} yorum işleniyor',
        subtitle: 'Duygu tonu, ilişki etiketleri ve tema işaretleri hesaplanıyor…',
      ),
    );

    int pos = 0, neu = 0, neg = 0;
    final relationMap = <String, int>{};
    final themeScores = _emptyThemeScores();
    final themeNegWeight = <String, int>{
      for (final k in _kThemeKeywords.keys) k: 0,
    };

    for (final e in entries) {
      final m = _moodBucket(e.mood);
      if (m == 1) {
        pos++;
      } else if (m == -1) {
        neg++;
      } else {
        neu++;
      }

      final relation = (e.relation ?? 'Belirsiz').trim();
      final relationKey = relation.isEmpty ? 'Belirsiz' : relation;
      relationMap[_displayRelation(relationKey)] =
          (relationMap[_displayRelation(relationKey)] ?? 0) + 1;

      final hits = _themeHits(e.textRaw);
      for (final entry in hits.entries) {
        themeScores[entry.key] = themeScores[entry.key]! + entry.value;
        if (m == -1) {
          themeNegWeight[entry.key] = themeNegWeight[entry.key]! + entry.value;
        }
      }
    }

    final total = entries.length;
    final topThemes = themeScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topRelations = relationMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final posPct = ((pos / total) * 100).round();
    final negPct = ((neg / total) * 100).round();
    final neuPct = ((neu / total) * 100).round();

    final relationBreakdown = topRelations
        .take(8)
        .map((r) => '${r.key}: ${r.value} yorum')
        .toList();

    final scores = AudienceScoreBreakdown.compute(
      pos: pos,
      neu: neu,
      neg: neg,
      total: total,
    );

    final weakest = _weakestThemes(themeScores, themeNegWeight);
    final surveyAgg = CreatorSurveyAggregate.fromEntries(entries);

    var intelligence = buildHeuristicCreatorReport(
      total: total,
      pos: pos,
      neu: neu,
      neg: neg,
      posPct: posPct,
      neuPct: neuPct,
      negPct: negPct,
      themeScores: themeScores,
      themeNegWeight: themeNegWeight,
      relationMap: relationMap,
      topThemes: topThemes,
      weakest: weakest,
      themeOrder: _kThemeKeywords.keys.toList(),
      surveyAggregate: surveyAgg,
    );

    final oa = OpenAiAudienceClient();
    if (oa.isConfigured) {
      final digest = await oa.collectPartialsDigest(
        entries,
        onChunkProgress: (index1Based, totalChunks) {
          onLoadUpdate?.call(
            AudienceAnalysisLoadState(
              phase: AudienceAnalysisLoadPhase.aiChunks,
              title: 'Yapay zekâ analizi',
              subtitle: 'Yorumlar parçalara bölündü; her parça sırayla işleniyor.',
              stepIndex: index1Based,
              stepTotal: totalChunks,
            ),
          );
        },
      );
      onLoadUpdate?.call(
        const AudienceAnalysisLoadState(
          phase: AudienceAnalysisLoadPhase.aiMerge,
          title: 'Creator Intelligence',
          subtitle: 'Parça özetleri ve rapor şeması birleştiriliyor…',
        ),
      );
      final aiReport = await oa.refineCreatorIntelligence(
        intelligence,
        partialsDigest: digest,
        surveyAggregateBlock: surveyAgg.toPromptBlock(),
      );
      intelligence = mergeCreatorWithAiOverlay(intelligence, aiReport);
    } else {
      onLoadUpdate?.call(
        const AudienceAnalysisLoadState(
          phase: AudienceAnalysisLoadPhase.buildingHeuristicReport,
          title: 'Rapor tamamlanıyor',
          subtitle: 'Yerel motor ile özet ve öneriler oluşturuluyor…',
        ),
      );
    }

    final summary = intelligence.executiveSummary;
    final narrativeInsight = (intelligence.strategicDigest != null &&
            intelligence.strategicDigest!.trim().isNotEmpty)
        ? intelligence.strategicDigest!
        : _buildPoolNarrative(
            total: total,
            pos: pos,
            neu: neu,
            neg: neg,
            posPct: posPct,
            neuPct: neuPct,
            negPct: negPct,
            topThemes: topThemes,
            themeNegWeight: themeNegWeight,
            relationMap: relationMap,
          );

    final themeBullets =
        intelligence.themeRows.map((e) => '${e.theme} — ${e.meaning}').toList();

    final actionBullets = <String>[
      ...intelligence.actionPlan.quickWins7d.map((s) => '[7 gün] $s'),
      ...intelligence.actionPlan.medium30d.map((s) => '[30 gün] $s'),
      ...intelligence.actionPlan.brand60d.map((s) => '[60 gün] $s'),
    ];

    final strengths = intelligence.benchmarkLines.isNotEmpty
        ? intelligence.benchmarkLines
        : _buildStrengths(topThemes, pos, neg, total);

    final developmentAreas = intelligence.topDiagnoses
        .map((d) => '${d.title}: ${d.detail}')
        .toList();

    final socialPersonalityGuidance = <String>[
      ...intelligence.segments.map((s) => '${s.segmentName} — ${s.action}'),
      ...intelligence.contentRecipe.map((c) => '%${c.percent} ${c.label}: ${c.detail}'),
      ...intelligence.replyTemplates.map((r) => 'Yanıt şablonu (${r.title}): ${r.text}'),
    ];

    try {
      await _data.saveAudienceScoreSnapshot(
        ownerId: ownerId,
        scores: scores,
        feedbackCount: total,
        positiveCount: pos,
        neutralCount: neu,
        negativeCount: neg,
        communityPerception: intelligence.cover.communityPerception,
        trust: intelligence.cover.trust,
        contentClarity: intelligence.cover.contentClarity,
        executiveSummary: intelligence.executiveSummary,
        creatorReport: intelligence,
      );
    } catch (e, st) {
      debugPrint('saveAudienceScoreSnapshot: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
    }

    return AudienceAnalysisResult(
      feedbackCount: total,
      positiveCount: pos,
      neutralCount: neu,
      negativeCount: neg,
      scores: scores,
      intelligence: intelligence,
      summary: summary,
      themeBullets: themeBullets,
      actionBullets: actionBullets,
      relationBreakdown: relationBreakdown,
      narrativeInsight: narrativeInsight,
      strengths: strengths,
      developmentAreas: developmentAreas,
      socialPersonalityGuidance: socialPersonalityGuidance,
    );
  }

  Map<String, int> _emptyThemeScores() {
    return {for (final k in _kThemeKeywords.keys) k: 0};
  }

  Map<String, int> _themeHits(String raw) {
    final text = raw.toLowerCase();
    final out = <String, int>{for (final k in _kThemeKeywords.keys) k: 0};
    for (final e in _kThemeKeywords.entries) {
      var score = 0;
      for (final w in e.value) {
        if (text.contains(w)) score++;
      }
      if (score > 0) {
        out[e.key] = score.clamp(1, 5);
      }
    }
    return out;
  }

  void _applyThemeScores(Map<String, int> themeScores, String raw, int mood) {
    final hits = _themeHits(raw);
    final weight = mood == -1 ? 2 : 1;
    for (final e in hits.entries) {
      if (e.value > 0) {
        themeScores[e.key] = themeScores[e.key]! + e.value * weight;
      }
    }
  }

  String _displayRelation(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'BELİRSİZ';
    final lower = t.toLowerCase();
    const map = {
      'arkadaş': 'ARKADAŞ',
      'arkadas': 'ARKADAŞ',
      'takipçi': 'TAKİPÇİ',
      'takipci': 'TAKİPÇİ',
      'iş arkadaşı': 'İŞ ARKADAŞI',
      'iş arkadaş': 'İŞ ARKADAŞI',
      'işarkadaşı': 'İŞ ARKADAŞI',
      'müşteri': 'MÜŞTERİ',
      'musteri': 'MÜŞTERİ',
      'aile': 'AİLE',
      'partner': 'PARTNER',
      'belirsiz': 'BELİRSİZ',
    };
    for (final e in map.entries) {
      if (lower == e.key || lower.contains(e.key)) return e.value;
    }
    return t.toUpperCase();
  }

  List<MapEntry<String, int>> _weakestThemes(
    Map<String, int> themeScores,
    Map<String, int> themeNegWeight,
  ) {
    final list = themeScores.entries.toList()
      ..sort((a, b) {
        final ra = themeNegWeight[a.key] ?? 0;
        final rb = themeNegWeight[b.key] ?? 0;
        if (rb != ra) return rb.compareTo(ra);
        return a.value.compareTo(b.value);
      });
    return list.take(3).toList();
  }

  List<String> _buildLinkActions({
    required int neg,
    required int neu,
    required int pos,
    required List<MapEntry<String, int>> sortedThemes,
  }) {
    final low = sortedThemes.isNotEmpty ? sortedThemes.last.key : 'İletişim ve netlik';
    return [
      if (neg > 0)
        'Öncelik: "$low" ile ilgili gelen olumsuz işaretleri bir sonraki 3 içerikte bilinçli olarak ele al (ör. daha net CTA, daha kısa mesaj).',
      if (neu > pos + neg)
        'Nötr yorumlar çoksa: daha güçlü duygusal çengeller (hikâye, soru, küçük anket) ile etkileşimi derinleştir.',
      'Bu linkten gelen örnekleri kaydet; bir sonraki kampanya döneminde aynı başlıkları tekrar ölç.',
    ];
  }

  String _buildLinkNarrative({
    required int total,
    required int pos,
    required int neu,
    required int neg,
    required String topTheme,
    required String secondTheme,
    required int socialHits,
    required Map<String, int> themeScores,
  }) {
    final buf = StringBuffer()
      ..writeln(
        'Bu geri bildirim seti, paylaştığın link üzerinden gelen $total yorumun '
        'genel tonunu ve öncelikli temalarını özetler. ',
      )
      ..writeln(
        'Duygu dağılımı olumlu $pos, nötr $neu, olumsuz $neg yorum olarak kaydedildi. ',
      )
      ..writeln(
        'Metinlerde en sık "$topTheme" ve "$secondTheme" başlıkları öne çıkıyor; '
        'bunlar izleyicinin zihninde seninle ilişkilendirdiği ana çerçeveyi gösterir. ',
      );
    if (socialHits >= total * 0.25) {
      buf.writeln(
        'Yorumların önemli bir kısmı sosyal medya, topluluk veya kişilik algısıyla '
        'ilişkilendirilen ifadeler içeriyor; bu da marka/kişilik algını doğrudan etkileyen geri bildirimler olduğunu gösterir. ',
      );
    }
    if (neg > 0) {
      buf.writeln(
        'Olumsuz tonlu yorumlar, özellikle iyileştirme fırsatı olan alanları '
        'işaret eder; bunları savunma yerine net aksiyon maddelerine dönüştürmek uzun vadede güveni artırır. ',
      );
    } else {
      buf.writeln(
        'Şu an için belirgin olumsuz ton yok; bu iyi bir temel—tutarlılığı ve '
        'şeffaflığı koruyarak büyümeye devam edebilirsin. ',
      );
    }
    return buf.toString().trim();
  }

  String _buildPoolNarrative({
    required int total,
    required int pos,
    required int neu,
    required int neg,
    required int posPct,
    required int neuPct,
    required int negPct,
    required List<MapEntry<String, int>> topThemes,
    required Map<String, int> themeNegWeight,
    required Map<String, int> relationMap,
  }) {
    final negTop = themeNegWeight.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topRel = relationMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final t1 = topThemes.first.key;
    final t2 = topThemes.length > 1 ? topThemes[1].key : t1;

    final buf = StringBuffer();

    buf.writeln('▸ Stratejik özet');
    buf.writeln(
      'Bu rapor, sosyal medya ve topluluk iletişimi perspektifinden okunmalı. '
      '$total geri bildirimlik örneklemde duygu haritası: %$posPct olumlu, %$neuPct nötr, %$negPct olumsuz. '
      '${neuPct >= 45 ? "Nötr ağırlığı yüksek; kitle henüz net taraf seçmemiş veya mesajın orta yolda tutulduğu bir dönemdesin." : ""}'
      '${negPct > posPct ? " Olumsuz ton, çözülmesi gereken sürtünme alanlarına işaret ediyor." : ""}'
      '${posPct >= 35 ? " Olumlu pay güçlü; marka vaadini büyütmek için iyi bir zemin var." : ""}',
    );

    buf.writeln();
    buf.writeln('▸ İzleyici teşhisi (tema eksenleri)');
    buf.writeln(
      topThemes.length > 1
          ? 'İzleyici zihninde en çok çakışan iki eksen "$t1" ve "$t2". '
              'Bunlar içerik planını, başlığı ve ilk 3 saniyelik kancayı birlikte düşünmen gerektiğini gösteriyor.'
          : 'Baskın eksen "$t1"; tüm içerik akışını bu vaat etrafında sadeleştirmek mesajını güçlendirir.',
    );

    if (neg > 0 && negTop.first.value > 0) {
      buf.writeln();
      buf.writeln('▸ Risk ve iyileştirme odağı');
      buf.writeln(
        'Olumsuz tonlu yorumlarda "${negTop.first.key}" çerçevesi öne çıkıyor. '
        'Burada hedef “daha fazla içerik” değil; tutarlı ton, net beklenti ve sunum kalitesiyle '
        'itibar riskini düşürmek. Küçük ama ölçülebilir düzeltmeler (ör. 2 haftalık tek alt başlık) genelde daha iyi sonuç verir.',
      );
    }

    if (topRel.isNotEmpty) {
      buf.writeln();
      buf.writeln('▸ Kitle kırılımı');
      buf.writeln(
        'En yüksek hacim "${topRel.first.key}" kaynaklı görüşlerde. Bu grup hem sadakat hem de eleştiri taşıyabilir; '
        'yanıtlarında şeffaflık ve tek tip şablon (teşekkür + net düzeltme + adım) profesyonel algı yaratır.',
      );
    }

    buf.writeln();
    buf.writeln('▸ Sonraki adım (danışman notu)');
    buf.writeln(
      'Aynı ölçümü 3–4 hafta sonra tekrarla; duygu yüzdelerindeki kayma ve tema sıralamasındaki değişim, '
      'stratejinin işe yarayıp yaramadığını gösteren asıl KPI’dır.',
    );

    return buf.toString().trim();
  }

  List<String> _buildStrengths(
    List<MapEntry<String, int>> topThemes,
    int pos,
    int neg,
    int total,
  ) {
    if (total == 0) return [];
    final out = <String>[];
    if (pos >= neg && pos > 0) {
      out.add(
        'Duygu dengesinde olumlu taraf en az olumsuz kadar güçlü (veya üstünde); '
        'bu, içerik–kişilik uyumunun bir kısmıyla kitleyi taşıdığını gösterir — “sürdürülebilir itibar” sinyali.',
      );
    }
    if (topThemes.first.value > 0) {
      out.add(
        '“${topThemes.first.key}” ekseninde tekrarlayan olumlu işaretler, profil ve üst funnel’da (bio, kapak, ilk cümle) '
        'aynı vaadi tekrar etmek için somut kanca sağlıyor.',
      );
    }
    if (topThemes.length > 1 && topThemes[1].value > 0) {
      out.add(
        'İkinci sıradaki “${topThemes[1].key}” teması, içerik çeşitlendirmesinde (format, süre, ton) deney yapmak için güvenli bir alan sunuyor.',
      );
    }
    if (out.isEmpty) {
      out.add(
        'Çoklu ilişki ve bakış açısından gelen örneklem, ileride daha keskin strateji için iyi bir başlangıç noktası.',
      );
    }
    return out.take(4).toList();
  }

}

/// Global instance (app_state'ta da eklenebilir).
final reportService = ReportService();
