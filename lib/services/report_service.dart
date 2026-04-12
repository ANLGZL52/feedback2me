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

  Future<ReportResult> generateReport(
    String linkId, {
    String languageCode = 'tr',
  }) async {
    String t(String tr, String en) => languageCode == 'en' ? en : tr;
    final entries = await _data.getFeedbacksForLink(linkId);
    final count = entries.length;

    if (entries.isEmpty) {
      return ReportResult(
        linkId: linkId,
        feedbackCount: 0,
        summary: t(
          'Henüz bu link için feedback yok.',
          'No feedback for this link yet.',
        ),
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

    final summary = t(
      'Bu link için $total yorum analiz edildi. Duygu dağılımı: %$posPct olumlu, '
          '%$neuPct nötr, %$negPct olumsuz. Öne çıkan başlıklar: "${top.key}" ve "${second.key}".',
      '$total comments were analyzed for this link. Sentiment: $posPct% positive, '
          '$neuPct% neutral, $negPct% negative. Leading themes: "${top.key}" and "${second.key}".',
    );

    final narrativeInsight = _buildLinkNarrative(
      total: total,
      pos: pos,
      neu: neu,
      neg: neg,
      topTheme: top.key,
      secondTheme: second.key,
      socialHits: socialHits,
      themeScores: themeScores,
      languageCode: languageCode,
    );

    final prioritizedActions = _buildLinkActions(
      neg: neg,
      neu: neu,
      pos: pos,
      sortedThemes: sortedThemes,
      languageCode: languageCode,
    );

    final texts = entries.map((e) => e.textRaw).where((t) => t.isNotEmpty).toList();
    final bullets = texts
        .take(5)
        .map((t) => t.length > 100 ? '${t.substring(0, 100)}…' : t)
        .toList();

    final themesList = sortedThemes
        .map(
          (e) => '${e.key}: ${e.value} ${t('eşleşme', 'matches')}',
        )
        .toList();

    return ReportResult(
      linkId: linkId,
      feedbackCount: count,
      summary: summary,
      themes: themesList,
      bullets: bullets,
      narrativeInsight: narrativeInsight,
      sentimentLine: t(
        'Olumlu: $pos • Nötr: $neu • Olumsuz: $neg',
        'Positive: $pos • Neutral: $neu • Negative: $neg',
      ),
      prioritizedActions: prioritizedActions,
    );
  }

  Future<AudienceAnalysisResult> generateAudienceAnalysis(
    String ownerId, {
    String? analyzedLinkId,
    void Function(AudienceAnalysisLoadState state)? onLoadUpdate,
    String languageCode = 'tr',
  }) async {
    String t(String tr, String en) => languageCode == 'en' ? en : tr;
    onLoadUpdate?.call(
      AudienceAnalysisLoadState(
        phase: AudienceAnalysisLoadPhase.fetchingComments,
        title: t('Yorum havuzu yükleniyor', 'Loading comment pool'),
        subtitle: t(
          'Sunucudan tüm geri bildirimler alınıyor…',
          'Fetching all feedback from the server…',
        ),
      ),
    );
    final entries = await _data.getAllFeedbacksForOwner(ownerId);
    if (entries.isEmpty) {
      return AudienceAnalysisResult(
        feedbackCount: 0,
        positiveCount: 0,
        neutralCount: 0,
        negativeCount: 0,
        summary: t(
          'Henüz yorum havuzunda veri yok. Analiz için linkini paylaşıp yorum toplamaya devam et.',
          'No data in the comment pool yet. Keep sharing your link to collect feedback for analysis.',
        ),
        themeBullets: [
          t(
            'Yeterli veri oluştuğunda temalar burada listelenecek.',
            'Themes will be listed here once there is enough data.',
          ),
        ],
        actionBullets: [
          t(
            'İlk hedef: en az 10–15 anlamlı yorum toplayarak örüntüleri güvenilir hale getir.',
            'First goal: gather at least 10–15 meaningful comments to make patterns reliable.',
          ),
        ],
        relationBreakdown: const [],
        narrativeInsight: t(
          'Yorum biriktiğinde; duygu dağılımı, temalar ve ilişki kırılımlarına göre '
              'sana özel bir özet ve gelişim önerileri burada oluşacak.',
          'As comments accumulate, a tailored summary and growth suggestions will appear here '
              'based on sentiment, themes, and relationship breakdowns.',
        ),
        strengths: const [],
        developmentAreas: [
          t(
            'Henüz değerlendirilecek yeterli geri bildirim yok.',
            'Not enough feedback to evaluate yet.',
          ),
        ],
        socialPersonalityGuidance: [
          t(
            'Linkini hedef kitlenle (bio, hikâye, sabit yorum) paylaşarak örneklem çeşitliliğini artır.',
            'Share your link with your audience (bio, story, pinned comment) to diversify the sample.',
          ),
        ],
        scores: AudienceScoreBreakdown.zero,
        intelligence: CreatorIntelligenceReport.empty(),
      );
    }

    onLoadUpdate?.call(
      AudienceAnalysisLoadState(
        phase: AudienceAnalysisLoadPhase.scanningComments,
        title: t(
          '${entries.length} yorum işleniyor',
          'Processing ${entries.length} comments',
        ),
        subtitle: t(
          'Duygu tonu, ilişki etiketleri ve tema işaretleri hesaplanıyor…',
          'Computing sentiment, relationship tags, and theme signals…',
        ),
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
        .map((r) => '${r.key}: ${r.value} ${t('yorum', 'comments')}')
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
    final outputEn = languageCode == 'en';
    if (oa.isConfigured) {
      final digest = await oa.collectPartialsDigest(
        entries,
        outputEnglishModel: outputEn,
        onChunkProgress: (index1Based, totalChunks) {
          onLoadUpdate?.call(
            AudienceAnalysisLoadState(
              phase: AudienceAnalysisLoadPhase.aiChunks,
              title: t('Yapay zekâ analizi', 'AI analysis'),
              subtitle: t(
                'Yorumlar parçalara bölündü; her parça sırayla işleniyor.',
                'Comments are split into chunks; each chunk is processed in order.',
              ),
              stepIndex: index1Based,
              stepTotal: totalChunks,
            ),
          );
        },
      );
      onLoadUpdate?.call(
        AudienceAnalysisLoadState(
          phase: AudienceAnalysisLoadPhase.aiMerge,
          title: t('Creator Intelligence', 'Creator Intelligence'),
          subtitle: t(
            'Parça özetleri ve rapor şeması birleştiriliyor…',
            'Merging chunk digests and report schema…',
          ),
        ),
      );
      final aiReport = await oa.refineCreatorIntelligence(
        intelligence,
        partialsDigest: digest,
        surveyAggregateBlock: surveyAgg.toPromptBlock(),
        outputEnglishModel: outputEn,
      );
      intelligence = mergeCreatorWithAiOverlay(intelligence, aiReport);
    } else {
      onLoadUpdate?.call(
        AudienceAnalysisLoadState(
          phase: AudienceAnalysisLoadPhase.buildingHeuristicReport,
          title: t('Rapor tamamlanıyor', 'Finishing report'),
          subtitle: t(
            'Yerel motor ile özet ve öneriler oluşturuluyor…',
            'Building summary and suggestions with the local engine…',
          ),
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
            languageCode: languageCode,
          );

    final themeBullets =
        intelligence.themeRows.map((e) => '${e.theme} — ${e.meaning}').toList();

    final d7 = outputEn ? '[7d]' : '[7 gün]';
    final d30 = outputEn ? '[30d]' : '[30 gün]';
    final d60 = outputEn ? '[60d]' : '[60 gün]';
    final actionBullets = <String>[
      ...intelligence.actionPlan.quickWins7d.map((s) => '$d7 $s'),
      ...intelligence.actionPlan.medium30d.map((s) => '$d30 $s'),
      ...intelligence.actionPlan.brand60d.map((s) => '$d60 $s'),
    ];

    final strengths = intelligence.benchmarkLines.isNotEmpty
        ? intelligence.benchmarkLines
        : _buildStrengths(topThemes, pos, neg, total, languageCode);

    final developmentAreas = intelligence.topDiagnoses
        .map((d) => '${d.title}: ${d.detail}')
        .toList();

    final socialPersonalityGuidance = <String>[
      ...intelligence.segments.map((s) => '${s.segmentName} — ${s.action}'),
      ...intelligence.contentRecipe.map((c) => '%${c.percent} ${c.label}: ${c.detail}'),
      ...intelligence.replyTemplates.map(
        (r) => t(
          'Yanıt şablonu (${r.title}): ${r.text}',
          'Reply template (${r.title}): ${r.text}',
        ),
      ),
    ];

    try {
      await _data.saveAudienceScoreSnapshot(
        ownerId: ownerId,
        scores: scores,
        feedbackCount: total,
        positiveCount: pos,
        neutralCount: neu,
        negativeCount: neg,
        analyzedLinkId: analyzedLinkId,
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
    required String languageCode,
  }) {
    String t(String tr, String en) => languageCode == 'en' ? en : tr;
    final low = sortedThemes.isNotEmpty
        ? sortedThemes.last.key
        : t('İletişim ve netlik', 'Communication and clarity');
    return [
      if (neg > 0)
        t(
          'Öncelik: "$low" ile ilgili gelen olumsuz işaretleri bir sonraki 3 içerikte bilinçli olarak ele al (ör. daha net CTA, daha kısa mesaj).',
          'Priority: deliberately address negative signals around "$low" in your next three posts (e.g. clearer CTA, shorter message).',
        ),
      if (neu > pos + neg)
        t(
          'Nötr yorumlar çoksa: daha güçlü duygusal çengeller (hikâye, soru, küçük anket) ile etkileşimi derinleştir.',
          'If neutral comments dominate: deepen engagement with stronger hooks (story, question, quick poll).',
        ),
      t(
        'Bu linkten gelen örnekleri kaydet; bir sonraki kampanya döneminde aynı başlıkları tekrar ölç.',
        'Save examples from this link and re-measure the same themes in your next campaign window.',
      ),
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
    required String languageCode,
  }) {
    String t(String tr, String en) => languageCode == 'en' ? en : tr;
    final buf = StringBuffer()
      ..writeln(
        t(
          'Bu geri bildirim seti, paylaştığın link üzerinden gelen $total yorumun '
              'genel tonunu ve öncelikli temalarını özetler. ',
          'This feedback set summarizes the overall tone and priority themes from $total comments on your shared link. ',
        ),
      )
      ..writeln(
        t(
          'Duygu dağılımı olumlu $pos, nötr $neu, olumsuz $neg yorum olarak kaydedildi. ',
          'Sentiment counts: positive $pos, neutral $neu, negative $neg. ',
        ),
      )
      ..writeln(
        t(
          'Metinlerde en sık "$topTheme" ve "$secondTheme" başlıkları öne çıkıyor; '
              'bunlar izleyicinin zihninde seninle ilişkilendirdiği ana çerçeveyi gösterir. ',
          'The themes "$topTheme" and "$secondTheme" appear most often—'
              'they show the main frame audiences associate with you. ',
        ),
      );
    if (socialHits >= total * 0.25) {
      buf.writeln(
        t(
          'Yorumların önemli bir kısmı sosyal medya, topluluk veya kişilik algısıyla '
              'ilişkilendirilen ifadeler içeriyor; bu da marka/kişilik algını doğrudan etkileyen geri bildirimler olduğunu gösterir. ',
          'A notable share of comments mention social, community, or personality cues—'
              'these directly shape brand and persona perception. ',
        ),
      );
    }
    if (neg > 0) {
      buf.writeln(
        t(
          'Olumsuz tonlu yorumlar, özellikle iyileştirme fırsatı olan alanları '
              'işaret eder; bunları savunma yerine net aksiyon maddelerine dönüştürmek uzun vadede güveni artırır. ',
          'Negative-tone comments flag improvement areas; turning them into clear actions (instead of debating) usually builds trust. ',
        ),
      );
    } else {
      buf.writeln(
        t(
          'Şu an için belirgin olumsuz ton yok; bu iyi bir temel—tutarlılığı ve '
              'şeffaflığı koruyarak büyümeye devam edebilirsin. ',
          'No strong negative tone right now—that is a solid base; keep consistency and transparency as you scale. ',
        ),
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
    required String languageCode,
  }) {
    String t(String tr, String en) => languageCode == 'en' ? en : tr;
    final negTop = themeNegWeight.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topRel = relationMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final t1 = topThemes.first.key;
    final t2 = topThemes.length > 1 ? topThemes[1].key : t1;

    final buf = StringBuffer();

    buf.writeln(t('▸ Stratejik özet', '▸ Strategic overview'));
    buf.writeln(
      t(
        'Bu rapor, sosyal medya ve topluluk iletişimi perspektifinden okunmalı. '
            '$total geri bildirimlik örneklemde duygu haritası: %$posPct olumlu, %$neuPct nötr, %$negPct olumsuz. '
            '${neuPct >= 45 ? "Nötr ağırlığı yüksek; kitle henüz net taraf seçmemiş veya mesajın orta yolda tutulduğu bir dönemdesin." : ""}'
            '${negPct > posPct ? " Olumsuz ton, çözülmesi gereken sürtünme alanlarına işaret ediyor." : ""}'
            '${posPct >= 35 ? " Olumlu pay güçlü; marka vaadini büyütmek için iyi bir zemin var." : ""}',
        'Read this report through a social and community lens. Across $total comments the map is '
            '$posPct% positive, $neuPct% neutral, $negPct% negative. '
            '${neuPct >= 45 ? "Neutral weight is high—the audience may be undecided or your message is landing in the middle." : ""}'
            '${negPct > posPct ? " Negative tone points to friction worth addressing." : ""}'
            '${posPct >= 35 ? " Positive share is solid—a good base to expand the brand promise." : ""}',
      ),
    );

    buf.writeln();
    buf.writeln(
      t(
        '▸ İzleyici teşhisi (tema eksenleri)',
        '▸ Audience diagnosis (theme axes)',
      ),
    );
    buf.writeln(
      topThemes.length > 1
          ? t(
              'İzleyici zihninde en çok çakışan iki eksen "$t1" ve "$t2". '
                  'Bunlar içerik planını, başlığı ve ilk 3 saniyelik kancayı birlikte düşünmen gerektiğini gösteriyor.',
              'Two axes clash most in the audience mind: "$t1" and "$t2". '
                  'Plan content, titles, and the first hook together around them.',
            )
          : t(
              'Baskın eksen "$t1"; tüm içerik akışını bu vaat etrafında sadeleştirmek mesajını güçlendirir.',
              'Dominant axis "$t1"; simplifying your feed around this promise strengthens the message.',
            ),
    );

    if (neg > 0 && negTop.first.value > 0) {
      buf.writeln();
      buf.writeln(
        t('▸ Risk ve iyileştirme odağı', '▸ Risk and improvement focus'),
      );
      buf.writeln(
        t(
          'Olumsuz tonlu yorumlarda "${negTop.first.key}" çerçevesi öne çıkıyor. '
              'Burada hedef “daha fazla içerik” değil; tutarlı ton, net beklenti ve sunum kalitesiyle '
              'itibar riskini düşürmek. Küçük ama ölçülebilir düzeltmeler (ör. 2 haftalık tek alt başlık) genelde daha iyi sonuç verir.',
          'Among negative comments the "${negTop.first.key}" frame stands out. '
              'Aim for consistent tone, clear expectations, and presentation quality—not "more posts". '
              'Small measurable tweaks (e.g. one sub-theme for two weeks) often outperform big vague changes.',
        ),
      );
    }

    if (topRel.isNotEmpty) {
      buf.writeln();
      buf.writeln(t('▸ Kitle kırılımı', '▸ Audience split'));
      buf.writeln(
        t(
          'En yüksek hacim "${topRel.first.key}" kaynaklı görüşlerde. Bu grup hem sadakat hem de eleştiri taşıyabilir; '
              'yanıtlarında şeffaflık ve tek tip şablon (teşekkür + net düzeltme + adım) profesyonel algı yaratır.',
          'Highest volume comes from "${topRel.first.key}". This group can carry loyalty and criticism; '
              'transparent replies with a simple template (thanks + clear fix + next step) read professional.',
        ),
      );
    }

    buf.writeln();
    buf.writeln(
      t('▸ Sonraki adım (danışman notu)', '▸ Next step (coach note)'),
    );
    buf.writeln(
      t(
        'Aynı ölçümü 3–4 hafta sonra tekrarla; duygu yüzdelerindeki kayma ve tema sıralamasındaki değişim, '
            'stratejinin işe yarayıp yaramadığını gösteren asıl KPI’dır.',
        'Re-run this measurement in 3–4 weeks; shifts in sentiment share and theme order are the real KPIs of whether strategy is working.',
      ),
    );

    return buf.toString().trim();
  }

  List<String> _buildStrengths(
    List<MapEntry<String, int>> topThemes,
    int pos,
    int neg,
    int total,
    String languageCode,
  ) {
    String t(String tr, String en) => languageCode == 'en' ? en : tr;
    if (total == 0) return [];
    final out = <String>[];
    if (pos >= neg && pos > 0) {
      out.add(
        t(
          'Duygu dengesinde olumlu taraf en az olumsuz kadar güçlü (veya üstünde); '
              'bu, içerik–kişilik uyumunun bir kısmıyla kitleyi taşıdığını gösterir — “sürdürülebilir itibar” sinyali.',
          'Positive sentiment is at least as strong as negative—a sign your content–persona fit is carrying part of the audience (a "sustainable reputation" signal).',
        ),
      );
    }
    if (topThemes.first.value > 0) {
      out.add(
        t(
          '“${topThemes.first.key}” ekseninde tekrarlayan olumlu işaretler, profil ve üst funnel’da (bio, kapak, ilk cümle) '
              'aynı vaadi tekrar etmek için somut kanca sağlıyor.',
          'Recurring positive signals on "${topThemes.first.key}" give concrete hooks to repeat the same promise in profile and top-of-funnel (bio, cover, first line).',
        ),
      );
    }
    if (topThemes.length > 1 && topThemes[1].value > 0) {
      out.add(
        t(
          'İkinci sıradaki “${topThemes[1].key}” teması, içerik çeşitlendirmesinde (format, süre, ton) deney yapmak için güvenli bir alan sunuyor.',
          'The second theme "${topThemes[1].key}" is a safer lane to experiment with format, length, and tone.',
        ),
      );
    }
    if (out.isEmpty) {
      out.add(
        t(
          'Çoklu ilişki ve bakış açısından gelen örneklem, ileride daha keskin strateji için iyi bir başlangıç noktası.',
          'Feedback from multiple relationships and viewpoints is a good starting point for sharper strategy later.',
        ),
      );
    }
    return out.take(4).toList();
  }

}

/// Global instance (app_state'ta da eklenebilir).
final reportService = ReportService();
