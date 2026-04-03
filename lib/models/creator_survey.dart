import 'dart:convert';

/// İçerik üreticisi geri bildirimi için isteğe bağlı yapılandırılmış bağlam.
/// Firestore `creatorSurvey` alanında saklanır.
class CreatorSurveyPayload {
  const CreatorSurveyPayload({
    this.familiarity,
    this.platforms = const [],
    this.watchFrequency,
    this.contentFocus = const [],
    this.scoreProduction,
    this.scoreClarity,
    this.scoreTrust,
    this.scoreEngagement,
    this.scoreConsistency,
  });

  /// Tanışıklık: first_time | short | medium | long
  final String? familiarity;

  /// Örn. instagram, tiktok, youtube, twitch, x, linkedin, other
  final List<String> platforms;

  /// Tüketim sıklığı: rare | monthly | weekly | daily
  final String? watchFrequency;

  /// Önerilen içerik yönleri (çoklu; “hangi türde daha iyi olabilir” seçimleri).
  final List<String> contentFocus;

  /// 1–5: üretim (ses/görüntü/kurgu genel algı)
  final int? scoreProduction;

  /// 1–5: mesaj netliği
  final int? scoreClarity;

  /// 1–5: güven / samimiyet algısı
  final int? scoreTrust;

  /// 1–5: eğlence / ilgi çekicilik
  final int? scoreEngagement;

  /// 1–5: tutarlılık / yayın düzeni algısı
  final int? scoreConsistency;

  static List<String> _stringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  static int? _clampLikert(dynamic v) {
    if (v == null) return null;
    final n = v is int ? v : int.tryParse(v.toString());
    if (n == null) return null;
    return n.clamp(1, 5);
  }

  factory CreatorSurveyPayload.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) {
      return const CreatorSurveyPayload();
    }
    return CreatorSurveyPayload(
      familiarity: m['familiarity'] as String?,
      platforms: _stringList(m['platforms']),
      watchFrequency: m['watchFrequency'] as String?,
      contentFocus: _stringList(m['contentFocus']),
      scoreProduction: _clampLikert(m['scoreProduction']),
      scoreClarity: _clampLikert(m['scoreClarity']),
      scoreTrust: _clampLikert(m['scoreTrust']),
      scoreEngagement: _clampLikert(m['scoreEngagement']),
      scoreConsistency: _clampLikert(m['scoreConsistency']),
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{};
    if (familiarity != null && familiarity!.isNotEmpty) {
      m['familiarity'] = familiarity;
    }
    if (platforms.isNotEmpty) m['platforms'] = platforms;
    if (watchFrequency != null && watchFrequency!.isNotEmpty) {
      m['watchFrequency'] = watchFrequency;
    }
    if (contentFocus.isNotEmpty) m['contentFocus'] = contentFocus;
    if (scoreProduction != null) m['scoreProduction'] = scoreProduction;
    if (scoreClarity != null) m['scoreClarity'] = scoreClarity;
    if (scoreTrust != null) m['scoreTrust'] = scoreTrust;
    if (scoreEngagement != null) m['scoreEngagement'] = scoreEngagement;
    if (scoreConsistency != null) m['scoreConsistency'] = scoreConsistency;
    return m;
  }

  /// Firestore’a yazılacak anlamlı veri var mı?
  bool get isEffectivelyEmpty => toMap().isEmpty;

  /// AI satırı için tek satırlık JSON (pipe ile çakışmayı azaltmak için escape yok; metin ayrı kolonda).
  String toCompactJson() => jsonEncode(toMap());
}
