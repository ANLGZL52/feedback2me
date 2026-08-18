import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
 import '../design_system/design_system.dart';
import '../models/creator_intelligence_report.dart';
import '../services/report_service.dart';

const Color _kGold = AppColors.primary;

/// Basit geri bildirim: tek satır duygu + "N kişi şunu istiyor" listesi.
class SimpleRequestSummaryView extends StatelessWidget {
  const SimpleRequestSummaryView({super.key, required this.summary});

  final SimpleRequestSummary summary;

  /// Sıcak, pozitif-önce açılış başlığı (duygu dağılımına göre).
  String _warmHeadline(BuildContext context) {
    final pos = summary.positiveCount;
    final neg = summary.negativeCount;
    if (pos >= neg && pos > 0) return L10n.get(context, 'warmHeadlinePositive');
    if (neg > pos) return L10n.get(context, 'warmHeadlineMixed');
    return L10n.get(context, 'warmHeadlineNeutral');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.feedbackCount > 0) ...[
          Text(
            _warmHeadline(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: _kGold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _SentimentLineCard(summary: summary),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.get(context, 'simpleSummaryTitle'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _kGold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (summary.topRequests.isEmpty && summary.otherRequests.isEmpty)
                  Text(
                    L10n.get(context, 'simpleSummaryEmpty'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary, height: 1.4),
                  )
                else ...[
                  if (summary.topRequests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        L10n.get(context, 'simpleSummaryLowSignal'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary, height: 1.4),
                      ),
                    ),
                  ...summary.topRequests
                      .map((r) => _RequestRow(request: r, emphasize: true)),
                  if (summary.otherRequests.isNotEmpty)
                    _OtherRequests(items: summary.otherRequests),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SentimentLineCard extends StatelessWidget {
  const _SentimentLineCard({required this.summary});

  final SimpleRequestSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppColors.surfaceSecondary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                L10n.get(context, 'simpleSummaryCommentsCount')
                    .replaceAll('{count}', '${summary.feedbackCount}'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _MoodChip(emoji: '👍', pct: summary.supportivePct),
            const SizedBox(width: 10),
            _MoodChip(emoji: '😐', pct: summary.neutralPct),
            const SizedBox(width: 10),
            _MoodChip(emoji: '👎', pct: summary.riskPct),
          ],
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.emoji, required this.pct});

  final String emoji;
  final int pct;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$emoji %$pct',
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, this.emphasize = false});

  final AudienceRequest request;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peopleWord = L10n.get(context, 'simpleSummaryPeopleWord');
    final example =
        request.examples.isNotEmpty ? request.examples.first.trim() : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: emphasize ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${request.count} $peopleWord',
              style: theme.textTheme.labelMedium?.copyWith(
                color: _kGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (example.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '“$example”',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherRequests extends StatelessWidget {
  const _OtherRequests({required this.items});

  final List<AudienceRequest> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: Text(
          L10n.get(context, 'simpleSummaryOther')
              .replaceAll('{count}', '${items.length}'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        children: items
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.count} ${L10n.get(context, 'simpleSummaryPeopleWord')}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
