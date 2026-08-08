// FeedbackToMe 2.0 — Topluluk özeti.
// AI YALNIZCA gerçek kullanıcı geri bildirimini yorumlar; içerik hakkında
// bağımsız/teknik değerlendirme ÜRETMEZ. Şema brief ile birebir uyumludur.

/// Topluluğun genel havası.
enum CommunityMood { positive, mixed, neutral, negative }

CommunityMood communityMoodFromString(String? s) {
  switch ((s ?? '').trim().toLowerCase()) {
    case 'positive':
      return CommunityMood.positive;
    case 'negative':
      return CommunityMood.negative;
    case 'mixed':
      return CommunityMood.mixed;
    case 'neutral':
    default:
      return CommunityMood.neutral;
  }
}

String communityMoodToString(CommunityMood m) => m.name;

/// AI güven düzeyi (az yorumda "low").
enum SummaryConfidence { low, medium, high }

SummaryConfidence summaryConfidenceFromString(String? s) {
  switch ((s ?? '').trim().toLowerCase()) {
    case 'high':
      return SummaryConfidence.high;
    case 'medium':
      return SummaryConfidence.medium;
    case 'low':
    default:
      return SummaryConfidence.low;
  }
}

String summaryConfidenceToString(SummaryConfidence c) => c.name;

/// Topluluk geri bildirim özeti — post/link için basit, sosyal, kısa çıktı.
///
/// AI alanları: [mood], [headline], [mostLiked], [mostMentioned],
/// [mixedOpinions], [hotTake], [shortSummary], [confidence].
/// Görsel/meta alanları (koddan hesaplanır, AI'dan bağımsız): [crowdScore],
/// [feedbackCount], [positive]/[neutral]/[negative], [reactionCounts],
/// [realComments], [aiUsed].
class CommunityFeedbackSummary {
  const CommunityFeedbackSummary({
    required this.mood,
    required this.headline,
    required this.mostLiked,
    required this.mostMentioned,
    required this.mixedOpinions,
    required this.hotTake,
    required this.shortSummary,
    required this.confidence,
    required this.crowdScore,
    required this.feedbackCount,
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.reactionCounts,
    required this.realComments,
    required this.aiUsed,
  });

  // --- AI çıktısı (yorumları yorumlar; üretmez) ---
  final CommunityMood mood;

  /// Kısa, sıcak başlık: "İnsanlar genel olarak sevmiş 🔥".
  final String headline;

  /// En sevilen konular (gerçek yorumlardan): ["Renkler", "Genel görünüm"].
  final List<String> mostLiked;

  /// En çok konuşulan/istenen konular: ["Yazı biraz daha belirgin olabilir"].
  final List<String> mostMentioned;

  /// Topluluğun ikiye bölündüğü konular (varsa).
  final List<String> mixedOpinions;

  /// Eğlenceli "hot take" — gerçek bir yorumdan seçili çarpıcı alıntı.
  final String hotTake;

  /// Tek-iki cümlelik samimi özet.
  final String shortSummary;

  /// AI güven düzeyi (az veri → low).
  final SummaryConfidence confidence;

  // --- Görsel/meta (koddan; AI'dan bağımsız) ---

  /// Tek genel skor 0–10 (ör. 8.4). Yeterli veri yoksa null.
  final double? crowdScore;

  final int feedbackCount;
  final int positive;
  final int neutral;
  final int negative;

  /// Emoji reaction dağılımı: {"🔥": 41, "❤️": 28, ...}.
  final Map<String, int> reactionCounts;

  /// Gösterilecek birkaç gerçek yorum (kullanıcı "otomatik" hissetmesin diye).
  final List<String> realComments;

  /// AI kullanıldı mı (false ise sezgisel/yerel özet).
  final bool aiUsed;

  bool get isEmpty => feedbackCount == 0;

  int get totalReactions =>
      reactionCounts.values.fold<int>(0, (a, b) => a + b);

  CommunityFeedbackSummary copyWith({
    CommunityMood? mood,
    String? headline,
    List<String>? mostLiked,
    List<String>? mostMentioned,
    List<String>? mixedOpinions,
    String? hotTake,
    String? shortSummary,
    SummaryConfidence? confidence,
    double? crowdScore,
    int? feedbackCount,
    int? positive,
    int? neutral,
    int? negative,
    Map<String, int>? reactionCounts,
    List<String>? realComments,
    bool? aiUsed,
  }) {
    return CommunityFeedbackSummary(
      mood: mood ?? this.mood,
      headline: headline ?? this.headline,
      mostLiked: mostLiked ?? this.mostLiked,
      mostMentioned: mostMentioned ?? this.mostMentioned,
      mixedOpinions: mixedOpinions ?? this.mixedOpinions,
      hotTake: hotTake ?? this.hotTake,
      shortSummary: shortSummary ?? this.shortSummary,
      confidence: confidence ?? this.confidence,
      crowdScore: crowdScore ?? this.crowdScore,
      feedbackCount: feedbackCount ?? this.feedbackCount,
      positive: positive ?? this.positive,
      neutral: neutral ?? this.neutral,
      negative: negative ?? this.negative,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      realComments: realComments ?? this.realComments,
      aiUsed: aiUsed ?? this.aiUsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'mood': communityMoodToString(mood),
        'headline': headline,
        'mostLiked': mostLiked,
        'mostMentioned': mostMentioned,
        'mixedOpinions': mixedOpinions,
        'hotTake': hotTake,
        'shortSummary': shortSummary,
        'confidence': summaryConfidenceToString(confidence),
        'crowdScore': crowdScore,
        'feedbackCount': feedbackCount,
        'positive': positive,
        'neutral': neutral,
        'negative': negative,
        'reactionCounts': reactionCounts,
        'realComments': realComments,
        'aiUsed': aiUsed,
      };

  factory CommunityFeedbackSummary.fromJson(Map<String, dynamic> j) {
    List<String> strList(String key) =>
        (j[key] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [];
    final rc = <String, int>{};
    final rawRc = j['reactionCounts'];
    if (rawRc is Map) {
      rawRc.forEach((k, v) {
        final n = (v as num?)?.round() ?? 0;
        if (n > 0) rc[k.toString()] = n;
      });
    }
    return CommunityFeedbackSummary(
      mood: communityMoodFromString(j['mood']?.toString()),
      headline: j['headline']?.toString() ?? '',
      mostLiked: strList('mostLiked'),
      mostMentioned: strList('mostMentioned'),
      mixedOpinions: strList('mixedOpinions'),
      hotTake: j['hotTake']?.toString() ?? '',
      shortSummary: j['shortSummary']?.toString() ?? '',
      confidence: summaryConfidenceFromString(j['confidence']?.toString()),
      crowdScore: (j['crowdScore'] as num?)?.toDouble(),
      feedbackCount: (j['feedbackCount'] as num?)?.round() ?? 0,
      positive: (j['positive'] as num?)?.round() ?? 0,
      neutral: (j['neutral'] as num?)?.round() ?? 0,
      negative: (j['negative'] as num?)?.round() ?? 0,
      reactionCounts: rc,
      realComments: strList('realComments'),
      aiUsed: j['aiUsed'] == true,
    );
  }

  static CommunityFeedbackSummary empty() => const CommunityFeedbackSummary(
        mood: CommunityMood.neutral,
        headline: '',
        mostLiked: [],
        mostMentioned: [],
        mixedOpinions: [],
        hotTake: '',
        shortSummary: '',
        confidence: SummaryConfidence.low,
        crowdScore: null,
        feedbackCount: 0,
        positive: 0,
        neutral: 0,
        negative: 0,
        reactionCounts: {},
        realComments: [],
        aiUsed: false,
      );
}
