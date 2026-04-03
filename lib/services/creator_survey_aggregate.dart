import '../models/feedback_entry.dart';

/// Tüm yorumlardan yapılandırılmış anket özetini çıkarır (AI + heuristik metinler için).
class CreatorSurveyAggregate {
  CreatorSurveyAggregate({
    required this.totalFeedbacks,
    required this.feedbacksWithSurvey,
    required this.platformCounts,
    required this.familiarityCounts,
    required this.frequencyCounts,
    required this.focusRecommendationCounts,
    required this.avgProduction,
    required this.avgClarity,
    required this.avgTrust,
    required this.avgEngagement,
    required this.avgConsistency,
  });

  final int totalFeedbacks;
  final int feedbacksWithSurvey;
  final Map<String, int> platformCounts;
  final Map<String, int> familiarityCounts;
  final Map<String, int> frequencyCounts;
  final Map<String, int> focusRecommendationCounts;
  final double? avgProduction;
  final double? avgClarity;
  final double? avgTrust;
  final double? avgEngagement;
  final double? avgConsistency;

  bool get isEmpty => feedbacksWithSurvey == 0;

  static CreatorSurveyAggregate fromEntries(List<FeedbackEntry> entries) {
    final total = entries.length;
    var withS = 0;
    final platforms = <String, int>{};
    final fam = <String, int>{};
    final freq = <String, int>{};
    final focus = <String, int>{};
    final prod = <int>[];
    final clar = <int>[];
    final trust = <int>[];
    final eng = <int>[];
    final cons = <int>[];

    for (final e in entries) {
      final s = e.creatorSurvey;
      if (s == null || s.isEffectivelyEmpty) continue;
      withS++;
      for (final p in s.platforms) {
        platforms[p] = (platforms[p] ?? 0) + 1;
      }
      if (s.familiarity != null && s.familiarity!.isNotEmpty) {
        fam[s.familiarity!] = (fam[s.familiarity!] ?? 0) + 1;
      }
      if (s.watchFrequency != null && s.watchFrequency!.isNotEmpty) {
        freq[s.watchFrequency!] = (freq[s.watchFrequency!] ?? 0) + 1;
      }
      for (final f in s.contentFocus) {
        focus[f] = (focus[f] ?? 0) + 1;
      }
      if (s.scoreProduction != null) prod.add(s.scoreProduction!);
      if (s.scoreClarity != null) clar.add(s.scoreClarity!);
      if (s.scoreTrust != null) trust.add(s.scoreTrust!);
      if (s.scoreEngagement != null) eng.add(s.scoreEngagement!);
      if (s.scoreConsistency != null) cons.add(s.scoreConsistency!);
    }

    double? avg(List<int> xs) {
      if (xs.isEmpty) return null;
      return xs.reduce((a, b) => a + b) / xs.length;
    }

    return CreatorSurveyAggregate(
      totalFeedbacks: total,
      feedbacksWithSurvey: withS,
      platformCounts: platforms,
      familiarityCounts: fam,
      frequencyCounts: freq,
      focusRecommendationCounts: focus,
      avgProduction: avg(prod),
      avgClarity: avg(clar),
      avgTrust: avg(trust),
      avgEngagement: avg(eng),
      avgConsistency: avg(cons),
    );
  }

  static String _topKeys(Map<String, int> m, int take) {
    if (m.isEmpty) return '—';
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(take).map((e) => '${e.key} (${e.value})').join(', ');
  }

  /// AI refine ve parça özetleri için düz metin blok.
  String toPromptBlock() {
    if (isEmpty) {
      return 'Yapılandırılmış anket: Bu havuzda henüz anket alanı doldurulmuş yorum yok veya veri çok az. '
          'Analizi yorum metinleri ve duygu dağılımına dayandır.';
    }
    final buf = StringBuffer()
      ..writeln(
        'Anket dolduran yorum sayısı: $feedbacksWithSurvey / $totalFeedbacks toplam yorum.',
      )
      ..writeln('Platform (çoklu sayım): ${_topKeys(platformCounts, 8)}')
      ..writeln('Takip süresi (familiarity): ${_topKeys(familiarityCounts, 4)}')
      ..writeln('Tüketim sıklığı: ${_topKeys(frequencyCounts, 4)}')
      ..writeln('"Hangi türde daha iyi olabilir" önerileri (içerik türü): ${_topKeys(focusRecommendationCounts, 8)}')
      ..writeln(
        'Likert ortalamaları (1-5, yalnızca doldurulanlar): '
        'üretim ${avgProduction?.toStringAsFixed(2) ?? '—'}, '
        'netlik ${avgClarity?.toStringAsFixed(2) ?? '—'}, '
        'güven ${avgTrust?.toStringAsFixed(2) ?? '—'}, '
        'eğlence/ilgi ${avgEngagement?.toStringAsFixed(2) ?? '—'}, '
        'tutarlılık ${avgConsistency?.toStringAsFixed(2) ?? '—'}.',
      );
    return buf.toString().trim();
  }
}
