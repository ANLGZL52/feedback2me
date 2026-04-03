import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/audience_score.dart';

const Color _kAccent = Color(0xFFD4AF37);

/// Büyük genel puan + üç alt metrik + isteğe bağlı önceki analize göre fark.
class AudienceScoreSummaryCard extends StatelessWidget {
  const AudienceScoreSummaryCard({
    super.key,
    required this.scores,
    this.deltaFromPrevious,
  });

  final AudienceScoreBreakdown scores;
  /// Bir önceki kayıttan genel puandaki fark (null = gösterme / ilk kayıt).
  final int? deltaFromPrevious;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dinleyici gelişim puanı',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: _kAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Olumlu oran, olumsuz baskı ve yorum hacmine göre hesaplanır; '
                        'her “analiz oluştur” çalıştırmasında kayıt tutulur.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (deltaFromPrevious != null) ...[
                  const SizedBox(width: 8),
                  _DeltaChip(delta: deltaFromPrevious!),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${scores.overall}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Text(
                    '/ 100',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MetricRow(
              label: 'Olumlu ivme',
              value: scores.positiveMomentum,
              icon: Icons.trending_up_rounded,
            ),
            const SizedBox(height: 10),
            _MetricRow(
              label: 'Olumsuz kontrol',
              value: scores.riskControl,
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 10),
            _MetricRow(
              label: 'Örneklem gücü',
              value: scores.dataDepth,
              icon: Icons.groups_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta});

  final int delta;

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final color = up ? const Color(0xFF4ADE80) : const Color(0xFFF87171);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${up ? '+' : ''}$delta',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kAccent.withValues(alpha: 0.85)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
        ),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              color: _kAccent.withValues(alpha: 0.85),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

/// Son iki kayıtlı analiz arasındaki farklar (önceki rapora göre).
class AudienceGrowthComparisonCard extends StatelessWidget {
  const AudienceGrowthComparisonCard({super.key, required this.history});

  final List<AudienceScoreSnapshot> history;

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Önceki rapora göre gelişim',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: _kAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'En az iki kez «Takipçi Yorum Analizi» çalıştırdığında; genel puan, '
                'duygu dağılımı ve (varsa) kapak üçlü metrikleri bir önceki kayıtla kıyaslanır.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cur = history[0];
    final prev = history[1];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Önceki rapora göre gelişim',
              style: theme.textTheme.titleSmall?.copyWith(
                color: _kAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Son analiz (${_formatDate(cur.createdAt)}), bir önceki (${_formatDate(prev.createdAt)}) ile kıyaslandı.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white54,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _GrowthDeltaRow(
              label: 'Genel gelişim puanı',
              delta: cur.scores.overall - prev.scores.overall,
            ),
            _GrowthDeltaRow(
              label: 'Olumlu ivme (skor)',
              delta: cur.scores.positiveMomentum - prev.scores.positiveMomentum,
            ),
            _GrowthDeltaRow(
              label: 'Olumsuz kontrol (skor)',
              delta: cur.scores.riskControl - prev.scores.riskControl,
            ),
            _GrowthDeltaRow(
              label: 'Örneklem gücü (skor)',
              delta: cur.scores.dataDepth - prev.scores.dataDepth,
            ),
            const SizedBox(height: 8),
            _GrowthDeltaRow(
              label: 'Olumlu yorum payı (%)',
              delta: cur.supportivePct - prev.supportivePct,
            ),
            _GrowthDeltaRow(
              label: 'Olumsuz yorum payı (%)',
              delta: cur.riskPct - prev.riskPct,
              lowerIsBetter: true,
            ),
            if (cur.communityPerception != null &&
                prev.communityPerception != null &&
                cur.trust != null &&
                prev.trust != null &&
                cur.contentClarity != null &&
                prev.contentClarity != null) ...[
              const SizedBox(height: 8),
              Text(
                'Kapak trio (rapor)',
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.white54),
              ),
              const SizedBox(height: 6),
              _GrowthDeltaRow(
                label: 'Topluluk algısı',
                delta: cur.communityPerception! - prev.communityPerception!,
              ),
              _GrowthDeltaRow(
                label: 'Güven',
                delta: cur.trust! - prev.trust!,
              ),
              _GrowthDeltaRow(
                label: 'İçerik netliği',
                delta: cur.contentClarity! - prev.contentClarity!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GrowthDeltaRow extends StatelessWidget {
  const _GrowthDeltaRow({
    required this.label,
    required this.delta,
    this.lowerIsBetter = false,
  });

  final String label;
  final int delta;
  /// true: negatif delta yeşil (ör. olumsuz payında düşüş)
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = lowerIsBetter ? delta <= 0 : delta >= 0;
    final color = delta == 0
        ? Colors.white54
        : (up ? const Color(0xFF4ADE80) : const Color(0xFFF87171));
    final icon = delta == 0
        ? Icons.horizontal_rule_rounded
        : (up ? Icons.trending_up_rounded : Icons.trending_down_rounded);
    final text = delta >= 0 ? '+$delta' : '$delta';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ),
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kayıtlı analizlerden basit çizgi grafik + liste.
class AudienceScoreHistorySection extends StatelessWidget {
  const AudienceScoreHistorySection({
    super.key,
    required this.history,
    this.onOpenSnapshot,
  });

  final List<AudienceScoreSnapshot> history;
  final void Function(AudienceScoreSnapshot snapshot)? onOpenSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    final scoresChrono = history.map((e) => e.scores.overall).toList().reversed.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gelişim geçmişi',
              style: theme.textTheme.titleSmall?.copyWith(
                color: _kAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              history.length >= 2
                  ? 'Yeni linklerle havuz büyüdükçe buradan zaman içindeki puan değişimini izleyebilirsin.'
                  : 'Bir sonraki analizde çizgi oluşur; düzenli çalıştırmak trendi netleştirir.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white54,
                height: 1.35,
              ),
            ),
            if (scoresChrono.length >= 2) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 100,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: scoresChrono,
                    color: _kAccent,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...history.take(24).map((s) {
              final dateStr =
                  '${s.createdAt.day.toString().padLeft(2, '0')}.${s.createdAt.month.toString().padLeft(2, '0')}.${s.createdAt.year} '
                  '${s.createdAt.hour.toString().padLeft(2, '0')}:${s.createdAt.minute.toString().padLeft(2, '0')}';
              final preview = (s.executiveSummary != null && s.executiveSummary!.trim().isNotEmpty)
                  ? s.executiveSummary!.trim()
                  : (s.creatorReport != null && s.creatorReport!.executiveSummary.trim().isNotEmpty)
                      ? s.creatorReport!.executiveSummary.trim()
                      : null;
              final tap = onOpenSnapshot;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: tap == null ? null : () => tap(s),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dateStr,
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                                ),
                              ),
                              Text(
                                '${s.scores.overall}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '· ${s.feedbackCount} yorum',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                              ),
                              if (tap != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Rapor ›',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _kAccent.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (preview != null && preview.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white38,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = 0.0;
    final maxV = 100.0;
    final n = values.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = n <= 1 ? 0.0 : i / (n - 1) * size.width;
      final t = (values[i].toDouble() - minV) / (maxV - minV);
      final y = size.height - t.clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
    final dotPaint = Paint()..color = color;
    final lastX = size.width;
    final lastT = (values.last.toDouble() - minV) / (maxV - minV);
    final lastY = size.height - lastT.clamp(0.0, 1.0) * size.height;
    canvas.drawCircle(Offset(lastX, lastY), 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return !listEquals(oldDelegate.values, values) || oldDelegate.color != color;
  }
}
