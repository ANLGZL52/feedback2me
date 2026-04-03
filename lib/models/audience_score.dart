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
    );
  }
}
