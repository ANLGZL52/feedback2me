// FeedbackToMe 2.0 — Tek "Crowd Score".
// Brief: kolay/hızlı/eğlenceli TEK genel skor (0–10). Teknik alt kriterlere
// bölünmez. Duygu oranından hesaplanır; varsa CreatorSurvey Likert ortalaması
// hafifçe harmanlanır.

import '../models/feedback_entry.dart';
import 'creator_survey_aggregate.dart';

class RatingService {
  const RatingService();

  /// Duygu sayımlarından temel skor (0–10): hepsi olumlu → 10, dengeli → 5,
  /// hepsi olumsuz → 0. Nötrler skoru 5'e çeker.
  static double _sentimentScore({
    required int positive,
    required int neutral,
    required int negative,
  }) {
    final total = positive + neutral + negative;
    if (total <= 0) return 5.0;
    // net = (pos - neg)/total ∈ [-1, 1] → 0..10
    final net = (positive - negative) / total;
    return (5.0 + net * 5.0).clamp(0.0, 10.0);
  }

  /// Likert ortalamalarının (1–5) ortalamasını 0–10'a ölçekler; veri yoksa null.
  static double? _likertScore(CreatorSurveyAggregate? agg) {
    if (agg == null || agg.isEmpty) return null;
    final vals = <double>[
      if (agg.avgProduction != null) agg.avgProduction!,
      if (agg.avgClarity != null) agg.avgClarity!,
      if (agg.avgTrust != null) agg.avgTrust!,
      if (agg.avgEngagement != null) agg.avgEngagement!,
      if (agg.avgConsistency != null) agg.avgConsistency!,
    ];
    if (vals.isEmpty) return null;
    final mean = vals.reduce((a, b) => a + b) / vals.length; // 1..5
    return (mean / 5.0 * 10.0).clamp(0.0, 10.0);
  }

  /// Tek genel skor 0–10 (bir ondalık). Yeterli veri yoksa null.
  ///
  /// Duygu skoru esas; Likert varsa %40 ağırlıkla harmanlanır.
  static double? crowdScore({
    required int positive,
    required int neutral,
    required int negative,
    CreatorSurveyAggregate? surveyAggregate,
  }) {
    final total = positive + neutral + negative;
    if (total <= 0) return null;
    final s = _sentimentScore(
      positive: positive,
      neutral: neutral,
      negative: negative,
    );
    final l = _likertScore(surveyAggregate);
    final blended = l == null ? s : (s * 0.6 + l * 0.4);
    // Tek ondalığa yuvarla (ör. 8.4).
    return (blended * 10).round() / 10;
  }

  /// Kolaylık: yorum kümesinden CreatorSurvey Likert'i toplayıp skoru hesaplar.
  static double? crowdScoreFromEntries({
    required List<FeedbackEntry> entries,
    required int positive,
    required int neutral,
    required int negative,
  }) {
    final agg = CreatorSurveyAggregate.fromEntries(entries);
    return crowdScore(
      positive: positive,
      neutral: neutral,
      negative: negative,
      surveyAggregate: agg,
    );
  }
}
