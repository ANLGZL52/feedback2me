import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'creator_intelligence_report.dart';

/// Takipçi havuzu analizinden türetilen 0–100 puanlar (AI metninden bağımsız, sayısal).
class AudienceScoreBreakdown {
  const AudienceScoreBreakdown({
    required this.overall,
    required this.positiveMomentum,
    required this.riskControl,
    required this.dataDepth,
  });

  /// Genel skor: üç alt metrik ortalaması.
  final int overall;
  /// Olumlu yorum oranı (0–100).
  final int positiveMomentum;
  /// Olumsuz oranın düşük olması (0–100).
  final int riskControl;
  /// Yorum hacmine göre örneklem güveni (0–100).
  final int dataDepth;

  static AudienceScoreBreakdown compute({
    required int pos,
    required int neu,
    required int neg,
    required int total,
  }) {
    if (total <= 0) return zero;
    final posShare = pos / total;
    final negShare = neg / total;
    final pm = (posShare * 100).round().clamp(0, 100);
    final rc = ((1 - negShare) * 100).round().clamp(0, 100);
    final dd = min(100, (20 + sqrt(total) * 1.45).round()).clamp(0, 100);
    final ov = ((pm + rc + dd) / 3).round().clamp(0, 100);
    return AudienceScoreBreakdown(
      overall: ov,
      positiveMomentum: pm,
      riskControl: rc,
      dataDepth: dd,
    );
  }

  static const AudienceScoreBreakdown zero = AudienceScoreBreakdown(
    overall: 0,
    positiveMomentum: 0,
    riskControl: 0,
    dataDepth: 0,
  );
}

/// Kayıtlı bir analiz anlık görüntüsü (gelişim grafiği + geçmiş rapor açma).
class AudienceScoreSnapshot {
  AudienceScoreSnapshot({
    required this.id,
    required this.createdAt,
    required this.scores,
    required this.feedbackCount,
    required this.positiveCount,
    required this.neutralCount,
    required this.negativeCount,
    this.communityPerception,
    this.trust,
    this.contentClarity,
    this.executiveSummary,
    this.creatorReport,
    this.analyzedLinkId,
  });

  final String id;
  final DateTime createdAt;
  final AudienceScoreBreakdown scores;
  final int feedbackCount;
  final int positiveCount;
  final int neutralCount;
  final int negativeCount;
  /// Kapak üçlüsü (gelişim kıyası); eski kayıtlarda null olabilir.
  final int? communityPerception;
  final int? trust;
  final int? contentClarity;
  final String? executiveSummary;
  /// Tam creator raporu; yoksa sadece skor satırı kaydıdır.
  final CreatorIntelligenceReport? creatorReport;
  /// Analizin üretildiği link id (aynı link için tekrar AI üretimini engellemek için).
  final String? analyzedLinkId;

  AudienceScoreSnapshot copyWith({
    CreatorIntelligenceReport? creatorReport,
    String? executiveSummary,
  }) {
    return AudienceScoreSnapshot(
      id: id,
      createdAt: createdAt,
      scores: scores,
      feedbackCount: feedbackCount,
      positiveCount: positiveCount,
      neutralCount: neutralCount,
      negativeCount: negativeCount,
      communityPerception: communityPerception,
      trust: trust,
      contentClarity: contentClarity,
      executiveSummary: executiveSummary ?? this.executiveSummary,
      creatorReport: creatorReport ?? this.creatorReport,
      analyzedLinkId: analyzedLinkId,
    );
  }

  int get supportivePct {
    if (feedbackCount <= 0) return 0;
    return ((100 * positiveCount) / feedbackCount).round();
  }

  int get undecidedPct {
    if (feedbackCount <= 0) return 0;
    return ((100 * neutralCount) / feedbackCount).round();
  }

  int get riskPct {
    if (feedbackCount <= 0) return 0;
    return ((100 * negativeCount) / feedbackCount).round();
  }

  /// [omitCreatorReport]: true ise `creatorReport` okunmaz (geçmiş listesi dinleyicisi;
  /// Web’de büyük JSON parse’ı INTERNAL ASSERTION tetikleyebilir).
  factory AudienceScoreSnapshot.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool omitCreatorReport = false,
  }) {
    final raw = data['createdAt'];
    final DateTime at;
    if (raw is Timestamp) {
      at = raw.toDate();
    } else if (raw is String) {
      at = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      at = DateTime.now();
    }
    CreatorIntelligenceReport? cr;
    if (!omitCreatorReport) {
      final crRaw = data['creatorReport'];
      if (crRaw is Map) {
        try {
          cr = CreatorIntelligenceReport.fromJson(
            Map<String, dynamic>.from(crRaw),
          );
        } catch (_) {
          cr = null;
        }
      }
    }
    return AudienceScoreSnapshot(
      id: id,
      createdAt: at,
      scores: AudienceScoreBreakdown(
        overall: (data['overallScore'] as num?)?.round() ?? 0,
        positiveMomentum: (data['positiveMomentum'] as num?)?.round() ?? 0,
        riskControl: (data['riskControl'] as num?)?.round() ?? 0,
        dataDepth: (data['dataDepth'] as num?)?.round() ?? 0,
      ),
      feedbackCount: (data['feedbackCount'] as num?)?.round() ?? 0,
      positiveCount: (data['positiveCount'] as num?)?.round() ?? 0,
      neutralCount: (data['neutralCount'] as num?)?.round() ?? 0,
      negativeCount: (data['negativeCount'] as num?)?.round() ?? 0,
      communityPerception: (data['communityPerception'] as num?)?.round(),
      trust: (data['trust'] as num?)?.round(),
      contentClarity: (data['contentClarity'] as num?)?.round(),
      executiveSummary: data['executiveSummary']?.toString(),
      creatorReport: cr,
      analyzedLinkId: data['analyzedLinkId']?.toString(),
    );
  }

  /// Railway REST liste öğesi (`overallScore` düz alanlar).
  factory AudienceScoreSnapshot.fromApiLite(Map<String, dynamic> m) {
    final at = DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now();
    return AudienceScoreSnapshot(
      id: m['id'] as String? ?? '',
      createdAt: at,
      scores: AudienceScoreBreakdown(
        overall: (m['overallScore'] as num?)?.round() ?? 0,
        positiveMomentum: (m['positiveMomentum'] as num?)?.round() ?? 0,
        riskControl: (m['riskControl'] as num?)?.round() ?? 0,
        dataDepth: (m['dataDepth'] as num?)?.round() ?? 0,
      ),
      feedbackCount: (m['feedbackCount'] as num?)?.round() ?? 0,
      positiveCount: (m['positiveCount'] as num?)?.round() ?? 0,
      neutralCount: (m['neutralCount'] as num?)?.round() ?? 0,
      negativeCount: (m['negativeCount'] as num?)?.round() ?? 0,
      communityPerception: (m['communityPerception'] as num?)?.round(),
      trust: (m['trust'] as num?)?.round(),
      contentClarity: (m['contentClarity'] as num?)?.round(),
      executiveSummary: m['executiveSummary']?.toString(),
      creatorReport: null,
      analyzedLinkId: m['analyzedLinkId']?.toString(),
    );
  }

  /// Railway REST detay (`scores` iç içe + `creatorReport`).
  factory AudienceScoreSnapshot.fromApiDetail(Map<String, dynamic> m) {
    final at = DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now();
    final scoresRaw = m['scores'];
    AudienceScoreBreakdown scores;
    if (scoresRaw is Map) {
      final sm = Map<String, dynamic>.from(scoresRaw);
      scores = AudienceScoreBreakdown(
        overall: (sm['overall'] as num?)?.round() ?? 0,
        positiveMomentum: (sm['positiveMomentum'] as num?)?.round() ?? 0,
        riskControl: (sm['riskControl'] as num?)?.round() ?? 0,
        dataDepth: (sm['dataDepth'] as num?)?.round() ?? 0,
      );
    } else {
      scores = AudienceScoreBreakdown(
        overall: (m['overallScore'] as num?)?.round() ?? 0,
        positiveMomentum: (m['positiveMomentum'] as num?)?.round() ?? 0,
        riskControl: (m['riskControl'] as num?)?.round() ?? 0,
        dataDepth: (m['dataDepth'] as num?)?.round() ?? 0,
      );
    }
    CreatorIntelligenceReport? cr;
    final crRaw = m['creatorReport'];
    if (crRaw is Map) {
      try {
        cr = CreatorIntelligenceReport.fromJson(
          Map<String, dynamic>.from(crRaw),
        );
      } catch (_) {
        cr = null;
      }
    }
    return AudienceScoreSnapshot(
      id: m['id'] as String? ?? '',
      createdAt: at,
      scores: scores,
      feedbackCount: (m['feedbackCount'] as num?)?.round() ?? 0,
      positiveCount: (m['positiveCount'] as num?)?.round() ?? 0,
      neutralCount: (m['neutralCount'] as num?)?.round() ?? 0,
      negativeCount: (m['negativeCount'] as num?)?.round() ?? 0,
      communityPerception: (m['communityPerception'] as num?)?.round(),
      trust: (m['trust'] as num?)?.round(),
      contentClarity: (m['contentClarity'] as num?)?.round(),
      executiveSummary: m['executiveSummary']?.toString(),
      creatorReport: cr,
      analyzedLinkId: m['analyzedLinkId']?.toString(),
    );
  }
}
