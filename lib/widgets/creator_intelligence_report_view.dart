import 'package:flutter/material.dart';

import '../models/creator_intelligence_report.dart';
import '../services/report_service.dart';
import 'audience_score_widgets.dart';

const Color _kGold = Color(0xFFD4AF37);

/// Creator Intelligence — kartlı, aksiyon odaklı rapor gövdesi.
class CreatorIntelligenceReportView extends StatelessWidget {
  const CreatorIntelligenceReportView({
    super.key,
    required this.result,
    this.deltaFromPrevious,
  });

  final AudienceAnalysisResult result;
  final int? deltaFromPrevious;

  @override
  Widget build(BuildContext context) {
    final r = result.intelligence;
    final section = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: _kGold,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AudienceScoreSummaryCard(
          scores: result.scores,
          deltaFromPrevious: deltaFromPrevious,
        ),
        const SizedBox(height: 12),
        _CoverPillarCard(cover: r.cover),
        const SizedBox(height: 12),
        _ExecCard(title: 'Yönetici özeti', body: result.summary, sectionStyle: section),
        const SizedBox(height: 12),
        if (r.visualAndFormatInsight.trim().isNotEmpty) ...[
          _NarrativeBodyCard(
            title: 'Görünüm, format ve üretim',
            body: r.visualAndFormatInsight,
            sectionStyle: section,
          ),
          const SizedBox(height: 12),
        ],
        _DiagnosesCard(diagnoses: r.topDiagnoses, sectionStyle: section),
        const SizedBox(height: 12),
        _HeatMapCard(heat: r.heatMap, sectionStyle: section),
        const SizedBox(height: 12),
        _RiskOpportunityCard(block: r.riskOpportunity, sectionStyle: section),
        const SizedBox(height: 12),
        if (r.benchmarkLines.isNotEmpty)
          _BulletCard(title: 'Benchmark & uzman okuması', lines: r.benchmarkLines, sectionStyle: section),
        if (r.benchmarkLines.isNotEmpty) const SizedBox(height: 12),
        _ThemeTableCard(rows: r.themeRows, themeSignalTotal: r.themeSignalTotal, unique: r.uniqueCommentCount, sectionStyle: section),
        const SizedBox(height: 12),
        _SegmentsCard(segments: r.segments, sectionStyle: section),
        const SizedBox(height: 12),
        _RecipeCard(lines: r.contentRecipe, sectionStyle: section),
        const SizedBox(height: 12),
        _ActionTiersCard(plan: r.actionPlan, sectionStyle: section),
        const SizedBox(height: 12),
        _ReplyTemplatesCard(templates: r.replyTemplates, sectionStyle: section),
        const SizedBox(height: 12),
        _ReMeasureCard(items: r.reMeasureKpis, sectionStyle: section),
        const SizedBox(height: 12),
        _DigestCard(narrative: result.narrativeInsight, sectionStyle: section),
        const SizedBox(height: 12),
        if (r.comprehensiveCoachLetter.trim().isNotEmpty) ...[
          _NarrativeBodyCard(
            title: 'Sana özel değerlendirme',
            body: r.comprehensiveCoachLetter,
            sectionStyle: section,
            emphasize: true,
          ),
          const SizedBox(height: 12),
        ],
        _SentimentMiniCard(result: result, sectionStyle: section),
        if (result.strengths.isNotEmpty) ...[
          const SizedBox(height: 12),
          _BulletCard(title: 'Güçlü sinyaller', lines: result.strengths, sectionStyle: section),
        ],
      ],
    );
  }
}

class _CoverPillarCard extends StatelessWidget {
  const _CoverPillarCard({required this.cover});

  final CreatorCoverScores cover;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Algı skorları',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _kGold,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Takipçilerin seni nasıl okuduğuna dair üç ana gösterge.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _PillarGauge(label: 'Topluluk algı', value: cover.communityPerception),
                _PillarGauge(label: 'Güven', value: cover.trust),
                _PillarGauge(label: 'İçerik netliği', value: cover.contentClarity),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kGold.withValues(alpha: 0.35)),
                color: const Color(0xFF1A1816),
              ),
              child: Text(
                cover.oneLiner,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
              ),
            ),
            if (cover.subScores.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in cover.subScores.entries)
                    Chip(
                      label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      side: BorderSide(color: _kGold.withValues(alpha: 0.25)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillarGauge extends StatelessWidget {
  const _PillarGauge({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
          ),
          Text('/100', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 6,
              backgroundColor: Colors.white12,
              color: _kGold.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                  height: 1.2,
                ),
          ),
        ],
      ),
    );
  }
}

class _ExecCard extends StatelessWidget {
  const _ExecCard({required this.title, required this.body, this.sectionStyle});

  final String title;
  final String body;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: sectionStyle),
            const SizedBox(height: 10),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.48, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosesCard extends StatelessWidget {
  const _DiagnosesCard({required this.diagnoses, this.sectionStyle});

  final List<CriticalDiagnosis> diagnoses;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    if (diagnoses.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: _kGold.withValues(alpha: 0.9), size: 22),
                const SizedBox(width: 8),
                Text('En kritik 3 teşhis', style: sectionStyle),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < diagnoses.length; i++) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: EdgeInsets.only(bottom: i < diagnoses.length - 1 ? 10 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF22201C),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${diagnoses[i].title}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      diagnoses[i].detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            height: 1.42,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeatMapCard extends StatelessWidget {
  const _HeatMapCard({required this.heat, this.sectionStyle});

  final AudienceHeatMapData heat;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kitle sıcaklık haritası', style: sectionStyle),
            const SizedBox(height: 4),
            Text(
              'Duyguyu iş kararına çevirir.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 14),
            _heatRow(context, 'Destekleyici kitle', heat.supportivePct, const Color(0xFF4ADE80), heat.supportiveHint),
            const SizedBox(height: 10),
            _heatRow(context, 'Kararsız izleyici', heat.undecidedPct, const Color(0xFFFBBF24), heat.undecidedHint),
            const SizedBox(height: 10),
            _heatRow(context, 'Riskli / eleştirel', heat.riskPct, const Color(0xFFF87171), heat.riskHint),
          ],
        ),
      ),
    );
  }

  Widget _heatRow(BuildContext context, String label, int pct, Color color, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
            Text('%$pct', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 8,
            backgroundColor: Colors.white10,
            color: color.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 4),
        Text(hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54, height: 1.35)),
      ],
    );
  }
}

class _RiskOpportunityCard extends StatelessWidget {
  const _RiskOpportunityCard({required this.block, this.sectionStyle});

  final RiskOpportunityBlock block;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fırsat & risk', style: sectionStyle),
            const SizedBox(height: 12),
            _miniBox(context, Icons.trending_up_rounded, 'Bu dönemin fırsatı', block.opportunity, const Color(0xFF4ADE80)),
            const SizedBox(height: 10),
            _miniBox(context, Icons.warning_amber_rounded, 'Bu dönemin riski', block.risk, const Color(0xFFFBBF24)),
          ],
        ),
      ),
    );
  }

  Widget _miniBox(BuildContext context, IconData icon, String title, String text, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        color: accent.withValues(alpha: 0.08),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeTableCard extends StatelessWidget {
  const _ThemeTableCard({
    required this.rows,
    required this.themeSignalTotal,
    required this.unique,
    this.sectionStyle,
  });

  final List<ThemeInsightRow> rows;
  final int themeSignalTotal;
  final int unique;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tema motoru', style: sectionStyle),
            const SizedBox(height: 6),
            Text(
              'Toplam benzersiz yorum: $unique · Toplam tema işareti: $themeSignalTotal\n'
              'Not: Bir yorum birden fazla temada sayılabilir.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54, height: 1.35),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF2A2724)),
                columns: const [
                  DataColumn(label: Text('Tema', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  DataColumn(label: Text('Sinyal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  DataColumn(label: Text('Duygu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  DataColumn(label: Text('Ne anlama geliyor?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(SizedBox(width: 120, child: Text(r.theme, style: const TextStyle(fontSize: 12)))),
                        DataCell(Text(r.signalStrength, style: const TextStyle(fontSize: 12))),
                        DataCell(Text(r.sentimentDirection, style: const TextStyle(fontSize: 11))),
                        DataCell(SizedBox(width: 220, child: Text(r.meaning, style: const TextStyle(fontSize: 11, height: 1.3)))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentsCard extends StatelessWidget {
  const _SegmentsCard({required this.segments, this.sectionStyle});

  final List<SegmentInsight> segments;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yorumcu segmentleri', style: sectionStyle),
            const SizedBox(height: 12),
            for (final s in segments) ...[
              Text(s.segmentName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(s.description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70, height: 1.35)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _kGold.withValues(alpha: 0.08),
                  border: Border.all(color: _kGold.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: _kGold, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ne yap: ${s.action}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.lines, this.sectionStyle});

  final List<ContentRecipeLine> lines;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('İçerik performans reçetesi (14 gün)', style: sectionStyle),
            const SizedBox(height: 12),
            for (final l in lines) ...[
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text('%${l.percent}', style: TextStyle(color: _kGold, fontWeight: FontWeight.w800)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text(l.detail, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTiersCard extends StatelessWidget {
  const _ActionTiersCard({required this.plan, this.sectionStyle});

  final ActionPlanTiers plan;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aksiyon planı', style: sectionStyle),
            const SizedBox(height: 12),
            _tier(context, 'Hızlı kazanımlar — 7 gün', plan.quickWins7d, Icons.flash_on_rounded),
            const SizedBox(height: 12),
            _tier(context, 'Orta vade — 30 gün', plan.medium30d, Icons.date_range_rounded),
            const SizedBox(height: 12),
            _tier(context, 'Marka & sistem — 60 gün', plan.brand60d, Icons.flag_rounded),
          ],
        ),
      ),
    );
  }

  Widget _tier(BuildContext context, String title, List<String> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _kGold),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        for (final x in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(color: _kGold)),
                Expanded(child: Text(x, style: const TextStyle(height: 1.35, fontSize: 13))),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReplyTemplatesCard extends StatelessWidget {
  const _ReplyTemplatesCard({required this.templates, this.sectionStyle});

  final List<ReplyTemplateItem> templates;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hazır yanıt şablonları', style: sectionStyle),
            const SizedBox(height: 8),
            for (final t in templates)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(t.title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(t.text, style: const TextStyle(height: 1.4, fontSize: 13)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReMeasureCard extends StatelessWidget {
  const _ReMeasureCard({required this.items, this.sectionStyle});

  final List<ReMeasureItem> items;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sonraki ölçüm (KPI)', style: sectionStyle),
            const SizedBox(height: 8),
            Text(
              'Bir sonraki analizde şunlara bak: tekrar çalıştırılabilir gelişim aracı.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 10),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18, color: _kGold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(it.hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54, height: 1.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NarrativeBodyCard extends StatelessWidget {
  const _NarrativeBodyCard({
    required this.title,
    required this.body,
    this.sectionStyle,
    this.emphasize = false,
  });

  final String title;
  final String body;
  final TextStyle? sectionStyle;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: emphasize ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: emphasize ? _kGold.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      color: emphasize ? const Color(0xFF1C1A17) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: sectionStyle),
            const SizedBox(height: 8),
            ..._parseAudienceNarrativeBlocks(body, context),
          ],
        ),
      ),
    );
  }
}

class _DigestCard extends StatelessWidget {
  const _DigestCard({required this.narrative, this.sectionStyle});

  final String narrative;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stratejik özet', style: sectionStyle),
            const SizedBox(height: 8),
            ..._parseAudienceNarrativeBlocks(narrative, context),
          ],
        ),
      ),
    );
  }
}

class _SentimentMiniCard extends StatelessWidget {
  const _SentimentMiniCard({required this.result, this.sectionStyle});

  final AudienceAnalysisResult result;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    final t = result.feedbackCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Duygu sayıları', style: sectionStyle),
            const SizedBox(height: 8),
            Text('Olumlu: ${result.positiveCount} · Nötr: ${result.neutralCount} · Olumsuz: ${result.negativeCount} (toplam $t)'),
          ],
        ),
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  const _BulletCard({required this.title, required this.lines, this.sectionStyle});

  final String title;
  final List<String> lines;
  final TextStyle? sectionStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: sectionStyle),
            const SizedBox(height: 8),
            for (final s in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $s', style: const TextStyle(height: 1.35)),
              ),
          ],
        ),
      ),
    );
  }
}

/// ▸ başlıklı stratejik metni kart içinde bölümler.
List<Widget> _parseAudienceNarrativeBlocks(String raw, BuildContext context) {
  final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
        height: 1.52,
        color: Colors.white.withValues(alpha: 0.92),
      );
  final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
        color: _kGold,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      );
  final parts = raw.split('\n\n');
  final widgets = <Widget>[];
  for (final p in parts) {
    final t = p.trim();
    if (t.isEmpty) continue;
    final lines = t.split('\n');
    if (lines.isNotEmpty && lines.first.trimLeft().startsWith('▸')) {
      final titleLine = lines.first.replaceFirst(RegExp(r'^▸\s*'), '').trim();
      final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titleLine, style: titleStyle),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(body, style: base),
              ],
            ],
          ),
        ),
      );
    } else {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(t, style: base),
        ),
      );
    }
  }
  return widgets;
}
