// Creator Intelligence Report — ham veri → teşhis → strateji → eylem (UI + AI birleşimi).

/// Kapak: üç sütun skor + tek cümlelik yorum.
class CreatorCoverScores {
  const CreatorCoverScores({
    required this.communityPerception,
    required this.trust,
    required this.contentClarity,
    required this.oneLiner,
    required this.subScores,
  });

  /// Topluluk algı skoru 0–100
  final int communityPerception;
  /// Güven skoru 0–100
  final int trust;
  /// İçerik netliği skoru 0–100
  final int contentClarity;
  final String oneLiner;
  /// Alt göstergeler: güven, netlik, otorite, samimiyet, tutarlılık, dönüşüm potansiyeli
  final Map<String, int> subScores;

  Map<String, dynamic> toJson() => {
        'communityPerception': communityPerception,
        'trust': trust,
        'contentClarity': contentClarity,
        'oneLiner': oneLiner,
        'subScores': subScores,
      };

  factory CreatorCoverScores.fromJson(Map<String, dynamic> j) {
    final subs = (j['subScores'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), (v as num).round().clamp(0, 100)),
        ) ??
        <String, int>{};
    return CreatorCoverScores(
      communityPerception: (j['communityPerception'] as num?)?.round().clamp(0, 100) ?? 0,
      trust: (j['trust'] as num?)?.round().clamp(0, 100) ?? 0,
      contentClarity: (j['contentClarity'] as num?)?.round().clamp(0, 100) ?? 0,
      oneLiner: j['oneLiner']?.toString() ?? '',
      subScores: subs,
    );
  }
}

class AudienceHeatMapData {
  const AudienceHeatMapData({
    required this.supportivePct,
    required this.undecidedPct,
    required this.riskPct,
    required this.supportiveHint,
    required this.undecidedHint,
    required this.riskHint,
  });

  final int supportivePct;
  final int undecidedPct;
  final int riskPct;
  final String supportiveHint;
  final String undecidedHint;
  final String riskHint;

  Map<String, dynamic> toJson() => {
        'supportivePct': supportivePct,
        'undecidedPct': undecidedPct,
        'riskPct': riskPct,
        'supportiveHint': supportiveHint,
        'undecidedHint': undecidedHint,
        'riskHint': riskHint,
      };

  factory AudienceHeatMapData.fromJson(Map<String, dynamic> j) => AudienceHeatMapData(
        supportivePct: (j['supportivePct'] as num?)?.round() ?? 0,
        undecidedPct: (j['undecidedPct'] as num?)?.round() ?? 0,
        riskPct: (j['riskPct'] as num?)?.round() ?? 0,
        supportiveHint: j['supportiveHint']?.toString() ?? '',
        undecidedHint: j['undecidedHint']?.toString() ?? '',
        riskHint: j['riskHint']?.toString() ?? '',
      );
}

class CriticalDiagnosis {
  const CriticalDiagnosis({required this.title, required this.detail});

  final String title;
  final String detail;

  Map<String, dynamic> toJson() => {'title': title, 'detail': detail};

  factory CriticalDiagnosis.fromJson(Map<String, dynamic> j) => CriticalDiagnosis(
        title: j['title']?.toString() ?? '',
        detail: j['detail']?.toString() ?? '',
      );
}

class ThemeInsightRow {
  const ThemeInsightRow({
    required this.theme,
    required this.signalStrength,
    required this.sentimentDirection,
    required this.meaning,
  });

  final String theme;
  final String signalStrength;
  final String sentimentDirection;
  final String meaning;

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'signalStrength': signalStrength,
        'sentimentDirection': sentimentDirection,
        'meaning': meaning,
      };

  factory ThemeInsightRow.fromJson(Map<String, dynamic> j) => ThemeInsightRow(
        theme: j['theme']?.toString() ?? '',
        signalStrength: j['signalStrength']?.toString() ?? '',
        sentimentDirection: j['sentimentDirection']?.toString() ?? '',
        meaning: j['meaning']?.toString() ?? '',
      );
}

class SegmentInsight {
  const SegmentInsight({
    required this.segmentName,
    required this.description,
    required this.action,
  });

  final String segmentName;
  final String description;
  final String action;

  Map<String, dynamic> toJson() => {
        'segmentName': segmentName,
        'description': description,
        'action': action,
      };

  factory SegmentInsight.fromJson(Map<String, dynamic> j) => SegmentInsight(
        segmentName: j['segmentName']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        action: j['action']?.toString() ?? '',
      );
}

class ContentRecipeLine {
  const ContentRecipeLine({
    required this.percent,
    required this.label,
    required this.detail,
  });

  final int percent;
  final String label;
  final String detail;

  Map<String, dynamic> toJson() => {
        'percent': percent,
        'label': label,
        'detail': detail,
      };

  factory ContentRecipeLine.fromJson(Map<String, dynamic> j) => ContentRecipeLine(
        percent: (j['percent'] as num?)?.round().clamp(0, 100) ?? 0,
        label: j['label']?.toString() ?? '',
        detail: j['detail']?.toString() ?? '',
      );
}

class ActionPlanTiers {
  const ActionPlanTiers({
    required this.quickWins7d,
    required this.medium30d,
    required this.brand60d,
  });

  final List<String> quickWins7d;
  final List<String> medium30d;
  final List<String> brand60d;

  Map<String, dynamic> toJson() => {
        'quickWins7d': quickWins7d,
        'medium30d': medium30d,
        'brand60d': brand60d,
      };

  factory ActionPlanTiers.fromJson(Map<String, dynamic> j) {
    List<String> ls(String key) =>
        (j[key] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ??
            <String>[];
    return ActionPlanTiers(
      quickWins7d: ls('quickWins7d'),
      medium30d: ls('medium30d'),
      brand60d: ls('brand60d'),
    );
  }
}

class ReplyTemplateItem {
  const ReplyTemplateItem({required this.title, required this.text});

  final String title;
  final String text;

  Map<String, dynamic> toJson() => {'title': title, 'text': text};

  factory ReplyTemplateItem.fromJson(Map<String, dynamic> j) => ReplyTemplateItem(
        title: j['title']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
      );
}

class RiskOpportunityBlock {
  const RiskOpportunityBlock({required this.opportunity, required this.risk});

  final String opportunity;
  final String risk;

  Map<String, dynamic> toJson() => {'opportunity': opportunity, 'risk': risk};

  factory RiskOpportunityBlock.fromJson(Map<String, dynamic> j) => RiskOpportunityBlock(
        opportunity: j['opportunity']?.toString() ?? '',
        risk: j['risk']?.toString() ?? '',
      );
}

class ReMeasureItem {
  const ReMeasureItem({required this.label, required this.hint});

  final String label;
  final String hint;

  Map<String, dynamic> toJson() => {'label': label, 'hint': hint};

  factory ReMeasureItem.fromJson(Map<String, dynamic> j) => ReMeasureItem(
        label: j['label']?.toString() ?? '',
        hint: j['hint']?.toString() ?? '',
      );
}

/// Tam rapor — UI blokları.
class CreatorIntelligenceReport {
  const CreatorIntelligenceReport({
    required this.cover,
    required this.executiveSummary,
    required this.heatMap,
    required this.topDiagnoses,
    required this.themeRows,
    required this.segments,
    required this.contentRecipe,
    required this.actionPlan,
    required this.replyTemplates,
    required this.riskOpportunity,
    required this.benchmarkLines,
    required this.reMeasureKpis,
    required this.themeSignalTotal,
    required this.uniqueCommentCount,
    this.strategicDigest,
    this.visualAndFormatInsight = '',
    this.comprehensiveCoachLetter = '',
  });

  final CreatorCoverScores cover;
  final String executiveSummary;
  final AudienceHeatMapData heatMap;
  final List<CriticalDiagnosis> topDiagnoses;
  final List<ThemeInsightRow> themeRows;
  final List<SegmentInsight> segments;
  final List<ContentRecipeLine> contentRecipe;
  final ActionPlanTiers actionPlan;
  final List<ReplyTemplateItem> replyTemplates;
  final RiskOpportunityBlock riskOpportunity;
  final List<String> benchmarkLines;
  final List<ReMeasureItem> reMeasureKpis;
  /// Tema anahtar kelimesi eşleşmelerinin toplam ağırlığı
  final int themeSignalTotal;
  final int uniqueCommentCount;
  /// Kısa stratejik özet (▸ bölümleri tek yerde toplanabilir)
  final String? strategicDigest;

  /// Görünüm, kapak/thumbnail, kamera, ışık, kurgu, ses — anket + yorum birleşimi (AI zenginleştirir).
  final String visualAndFormatInsight;

  /// Sana hitap eden, kapanış “koç mektubu”: tüm sinyallerin sentezi.
  final String comprehensiveCoachLetter;

  Map<String, dynamic> toJson() => {
        'cover': cover.toJson(),
        'executiveSummary': executiveSummary,
        'heatMap': heatMap.toJson(),
        'topDiagnoses': topDiagnoses.map((e) => e.toJson()).toList(),
        'themeRows': themeRows.map((e) => e.toJson()).toList(),
        'segments': segments.map((e) => e.toJson()).toList(),
        'contentRecipe': contentRecipe.map((e) => e.toJson()).toList(),
        'actionPlan': actionPlan.toJson(),
        'replyTemplates': replyTemplates.map((e) => e.toJson()).toList(),
        'riskOpportunity': riskOpportunity.toJson(),
        'benchmarkLines': benchmarkLines,
        'reMeasureKpis': reMeasureKpis.map((e) => e.toJson()).toList(),
        'themeSignalTotal': themeSignalTotal,
        'uniqueCommentCount': uniqueCommentCount,
        'strategicDigest': strategicDigest,
        'visualAndFormatInsight': visualAndFormatInsight,
        'comprehensiveCoachLetter': comprehensiveCoachLetter,
      };

  factory CreatorIntelligenceReport.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> listMap(String key) =>
        (j[key] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
            <Map<String, dynamic>>[];

    return CreatorIntelligenceReport(
      cover: CreatorCoverScores.fromJson(Map<String, dynamic>.from(j['cover'] as Map? ?? {})),
      executiveSummary: j['executiveSummary']?.toString() ?? '',
      heatMap: AudienceHeatMapData.fromJson(Map<String, dynamic>.from(j['heatMap'] as Map? ?? {})),
      topDiagnoses: listMap('topDiagnoses').map(CriticalDiagnosis.fromJson).toList(),
      themeRows: listMap('themeRows').map(ThemeInsightRow.fromJson).toList(),
      segments: listMap('segments').map(SegmentInsight.fromJson).toList(),
      contentRecipe: listMap('contentRecipe').map(ContentRecipeLine.fromJson).toList(),
      actionPlan: ActionPlanTiers.fromJson(Map<String, dynamic>.from(j['actionPlan'] as Map? ?? {})),
      replyTemplates: listMap('replyTemplates').map(ReplyTemplateItem.fromJson).toList(),
      riskOpportunity:
          RiskOpportunityBlock.fromJson(Map<String, dynamic>.from(j['riskOpportunity'] as Map? ?? {})),
      benchmarkLines: (j['benchmarkLines'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      reMeasureKpis: listMap('reMeasureKpis').map(ReMeasureItem.fromJson).toList(),
      themeSignalTotal: (j['themeSignalTotal'] as num?)?.round() ?? 0,
      uniqueCommentCount: (j['uniqueCommentCount'] as num?)?.round() ?? 0,
      strategicDigest: j['strategicDigest']?.toString(),
      visualAndFormatInsight: j['visualAndFormatInsight']?.toString() ?? '',
      comprehensiveCoachLetter: j['comprehensiveCoachLetter']?.toString() ?? '',
    );
  }

  static CreatorIntelligenceReport empty() => CreatorIntelligenceReport(
        cover: const CreatorCoverScores(
          communityPerception: 0,
          trust: 0,
          contentClarity: 0,
          oneLiner: '',
          subScores: {},
        ),
        executiveSummary: '',
        heatMap: const AudienceHeatMapData(
          supportivePct: 0,
          undecidedPct: 0,
          riskPct: 0,
          supportiveHint: '',
          undecidedHint: '',
          riskHint: '',
        ),
        topDiagnoses: const [],
        themeRows: const [],
        segments: const [],
        contentRecipe: const [],
        actionPlan: const ActionPlanTiers(quickWins7d: [], medium30d: [], brand60d: []),
        replyTemplates: const [],
        riskOpportunity: const RiskOpportunityBlock(opportunity: '', risk: ''),
        benchmarkLines: const [],
        reMeasureKpis: const [],
        themeSignalTotal: 0,
        uniqueCommentCount: 0,
        strategicDigest: null,
        visualAndFormatInsight: '',
        comprehensiveCoachLetter: '',
      );
}
