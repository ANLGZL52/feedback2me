import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/app_localizations.dart';
import '../../models/community_feedback_summary.dart';

/// Feedback2Me V2 — Topluluk Özeti (aydınlık, insight-first).
///
/// YALNIZCA mevcut [CommunityFeedbackSummary] gerçek alanlarını gösterir:
/// crowdScore (0–10), feedbackCount, positive/neutral/negative, mood, headline,
/// shortSummary, mostLiked, mostMentioned, mixedOpinions, hotTake, confidence.
/// Yeni metrik/skor icat etmez; boş alanları GİZLER.
class CommunitySummaryV2View extends StatelessWidget {
  const CommunitySummaryV2View({
    super.key,
    required this.summary,
    this.onSeeComments,
  });

  final CommunityFeedbackSummary summary;
  final VoidCallback? onSeeComments;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final total = s.positive + s.neutral + s.negative;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scoreHeader(context),
        if (total > 0) ...[
          const SizedBox(height: AppSpacing.m),
          _SentimentDistribution(
              positive: s.positive, neutral: s.neutral, negative: s.negative),
        ],
        const SizedBox(height: AppSpacing.m),
        _whatCrowdSays(context),
        if (s.mostLiked.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          _ChipsSection(
              label: L10n.get(context, 'insightMostLoved'),
              items: s.mostLiked,
              tone: _ChipTone.positive),
        ],
        if (s.mostMentioned.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          _ChipsSection(
              label: L10n.get(context, 'insightMostMentioned'),
              items: s.mostMentioned,
              tone: _ChipTone.violet),
        ],
        if (s.mixedOpinions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          _ChipsSection(
              label: L10n.get(context, 'insightSplit'),
              items: s.mixedOpinions,
              tone: _ChipTone.neutral),
        ],
        if (s.hotTake.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          _hotTake(context),
        ],
        if (onSeeComments != null) ...[
          const SizedBox(height: AppSpacing.l),
          FeedbackPrimaryButton(
            label: L10n.get(context, 'insightSeeComments'),
            icon: Icons.forum_rounded,
            onPressed: onSeeComments,
          ),
        ],
      ],
    );
  }

  Widget _scoreHeader(BuildContext context) {
    final s = summary;
    final score = s.crowdScore;
    final based = L10n.get(context, 'insightBasedOn').replaceFirst(
        '{n}', '${s.feedbackCount}');
    return FeedbackCard(
      gradient: AppColors.primaryGradient,
      shadow: true,
      child: Column(
        children: [
          if (score != null) ...[
            RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: score.toStringAsFixed(1),
                    style: AppType.displayLarge
                        .copyWith(color: AppColors.onPrimary)),
                TextSpan(
                    text: '  / 10',
                    style: AppType.sectionTitle.copyWith(
                        color: AppColors.onPrimary.withValues(alpha: 0.8))),
              ]),
            ),
            const SizedBox(height: 2),
            Text(
              L10n.get(context, 'insightCrowdScore').toUpperCase(),
              style: AppType.caption.copyWith(
                  color: AppColors.onPrimary.withValues(alpha: 0.85),
                  letterSpacing: 1.1),
            ),
          ] else
            Text('${s.feedbackCount}',
                style:
                    AppType.displayLarge.copyWith(color: AppColors.onPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_moodEmoji(s.mood), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_moodLabel(context, s.mood),
                    style: AppType.bodyStrong
                        .copyWith(color: AppColors.onPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(based,
              style: AppType.caption
                  .copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _whatCrowdSays(BuildContext context) {
    final s = summary;
    return FeedbackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(L10n.get(context, 'insightWhatCrowdSays'),
                  style: AppType.sectionTitle),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(
            s.headline.isNotEmpty
                ? s.headline
                : L10n.get(context, 'insightCollecting'),
            style: AppType.cardTitle.copyWith(height: 1.3),
          ),
          if (s.shortSummary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(s.shortSummary, style: AppType.body.copyWith(height: 1.5)),
          ],
          if (s.confidence == SummaryConfidence.low) ...[
            const SizedBox(height: AppSpacing.s),
            Text(L10n.get(context, 'insightLowConfidence'),
                style: AppType.caption),
          ],
        ],
      ),
    );
  }

  Widget _hotTake(BuildContext context) {
    return FeedbackCard(
      color: AppColors.violetSoft,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🌶️  ${L10n.get(context, 'insightHotTake')}',
              style: AppType.sectionTitle.copyWith(color: AppColors.violet)),
          const SizedBox(height: AppSpacing.s),
          Text('“${summary.hotTake}”',
              style: AppType.body
                  .copyWith(fontStyle: FontStyle.italic, height: 1.45)),
        ],
      ),
    );
  }
}

String _moodLabel(BuildContext c, CommunityMood m) {
  switch (m) {
    case CommunityMood.positive:
      return L10n.get(c, 'moodOverallPositive');
    case CommunityMood.mixed:
      return L10n.get(c, 'moodOverallMixed');
    case CommunityMood.negative:
      return L10n.get(c, 'moodOverallNegative');
    case CommunityMood.neutral:
      return L10n.get(c, 'moodOverallNeutral');
  }
}

String _moodEmoji(CommunityMood m) => switch (m) {
      CommunityMood.positive => '😍',
      CommunityMood.mixed => '👀',
      CommunityMood.negative => '🤔',
      CommunityMood.neutral => '🙂',
    };

/// Duygu dağılımı — gerçek positive/neutral/negative sayımından (client aggregation).
class _SentimentDistribution extends StatelessWidget {
  const _SentimentDistribution({
    required this.positive,
    required this.neutral,
    required this.negative,
  });

  final int positive;
  final int neutral;
  final int negative;

  @override
  Widget build(BuildContext context) {
    final en = L10n.languageCodeForApp(context) == 'en';
    final total = positive + neutral + negative;
    final safe = total == 0 ? 1 : total;
    int pct(int v) => ((v / safe) * 100).round();
    String fmt(int p) => en ? '$p%' : '%$p';

    final posLabel = L10n.get(context, 'moodPositive');
    final neuLabel = L10n.get(context, 'moodNeutral');
    final negLabel = L10n.get(context, 'insightNeedsWork');

    return FeedbackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.get(context, 'insightSentiment'),
              style: AppType.sectionTitle),
          const SizedBox(height: AppSpacing.m),
          Semantics(
            label:
                '$posLabel ${fmt(pct(positive))}, $neuLabel ${fmt(pct(neutral))}, $negLabel ${fmt(pct(negative))}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  if (positive > 0)
                    Expanded(
                        flex: positive,
                        child: Container(height: 12, color: AppColors.success)),
                  if (neutral > 0)
                    Expanded(
                        flex: neutral,
                        child: Container(height: 12, color: AppColors.warning)),
                  if (negative > 0)
                    Expanded(
                        flex: negative,
                        child: Container(height: 12, color: AppColors.danger)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          _row(AppColors.success, posLabel, fmt(pct(positive))),
          _row(AppColors.warning, neuLabel, fmt(pct(neutral))),
          _row(AppColors.danger, negLabel, fmt(pct(negative))),
        ],
      ),
    );
  }

  Widget _row(Color c, String label, String pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppType.secondary)),
          Text(pct, style: AppType.bodyStrong),
        ],
      ),
    );
  }
}

enum _ChipTone { positive, violet, neutral }

class _ChipsSection extends StatelessWidget {
  const _ChipsSection({
    required this.label,
    required this.items,
    required this.tone,
  });

  final String label;
  final List<String> items;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) {
      _ChipTone.positive => AppColors.successSoft,
      _ChipTone.violet => AppColors.violetSoft,
      _ChipTone.neutral => AppColors.warningSoft,
    };
    final fg = switch (tone) {
      _ChipTone.positive => AppColors.success,
      _ChipTone.violet => AppColors.violet,
      _ChipTone.neutral => AppColors.warning,
    };
    return FeedbackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final it in items)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration:
                      BoxDecoration(color: bg, borderRadius: AppRadius.rPill),
                  child: Text(it,
                      style: AppType.secondary
                          .copyWith(color: fg, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// AI özeti hazırlanırken gösterilen V2 skeleton (3 insight kartı + metin).
class CommunitySummaryLoading extends StatelessWidget {
  const CommunitySummaryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(L10n.get(context, 'insightLoadingTitle'),
                  style: AppType.sectionTitle),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(L10n.get(context, 'insightLoadingSub'), style: AppType.secondary),
        const SizedBox(height: AppSpacing.l),
        for (var i = 0; i < 3; i++) ...[
          const _SkeletonCard(),
          const SizedBox(height: AppSpacing.m),
        ],
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return FeedbackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(120, 12),
          const SizedBox(height: 12),
          bar(double.infinity, 12),
          const SizedBox(height: 8),
          bar(double.infinity, 12),
          const SizedBox(height: 8),
          bar(180, 12),
        ],
      ),
    );
  }
}
