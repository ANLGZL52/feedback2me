import 'package:flutter/material.dart';

import '../../config/feedback_reactions.dart';
import '../../design_system/design_system.dart';
import '../../l10n/app_localizations.dart';
import '../../models/creator_survey.dart';
import '../../models/feedback_entry.dart';

/// V2 gerçek yorum kartı — reaction emoji + isim/Anonim + zaman + yorum metni
/// (+ opsiyonel "Ek bilgiler" creator survey). Backend alanları birebir okunur;
/// yeni alan/istatistik üretilmez.
class FeedbackCommentCard extends StatefulWidget {
  const FeedbackCommentCard({super.key, required this.entry});

  final FeedbackEntry entry;

  @override
  State<FeedbackCommentCard> createState() => _FeedbackCommentCardState();
}

class _FeedbackCommentCardState extends State<FeedbackCommentCard> {
  bool _expanded = false;

  Color _moodSoft(int? mood) => mood == 1
      ? AppColors.successSoft
      : mood == -1
          ? AppColors.dangerSoft
          : AppColors.warningSoft;

  Color _moodColor(int? mood) => mood == 1
      ? AppColors.success
      : mood == -1
          ? AppColors.danger
          : AppColors.warning;

  String _moodEmojiFallback(int? mood) =>
      mood == 1 ? '🙂' : (mood == -1 ? '🙁' : '😐');

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final en = L10n.languageCodeForApp(context) == 'en';
    final reaction = reactionByKey(e.reaction);
    final emoji = reaction?.emoji ?? _moodEmojiFallback(e.mood);
    final reactionLabel = reaction?.label(en);
    final name = (e.responderName != null && e.responderName!.trim().isNotEmpty)
        ? e.responderName!.trim()
        : L10n.get(context, 'commentAnonymous');
    final date = e.createdAt != null
        ? MaterialLocalizations.of(context).formatShortDate(e.createdAt!)
        : '';
    final survey = e.creatorSurvey;
    final hasSurvey = survey != null && !survey.isEffectivelyEmpty;

    return Semantics(
      label: '$name, ${reactionLabel ?? ''}. ${e.textRaw}',
      child: FeedbackCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _moodSoft(e.mood),
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: AppType.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (date.isNotEmpty)
                        Text(date, style: AppType.caption),
                    ],
                  ),
                ),
                if (reactionLabel != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _moodSoft(e.mood),
                      borderRadius: AppRadius.rPill,
                    ),
                    child: Text(reactionLabel,
                        style: AppType.caption.copyWith(
                            color: _moodColor(e.mood),
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(e.textRaw, style: AppType.body.copyWith(height: 1.5)),
            if (e.relation != null && e.relation!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(e.relation!.trim(), style: AppType.caption),
                ],
              ),
            ],
            if (hasSurvey) ...[
              const SizedBox(height: AppSpacing.s),
              InkWell(
                borderRadius: AppRadius.rSmall,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(L10n.get(context, 'pfExtraInfo'),
                          style: AppType.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              if (_expanded) _surveyDetail(context, survey),
            ],
          ],
        ),
      ),
    );
  }

  Widget _surveyDetail(BuildContext context, CreatorSurveyPayload s) {
    final scores = <MapEntry<String, int>>[
      if (s.scoreProduction != null)
        MapEntry(L10n.get(context, 'csProduction'), s.scoreProduction!),
      if (s.scoreClarity != null)
        MapEntry(L10n.get(context, 'csClarity'), s.scoreClarity!),
      if (s.scoreTrust != null)
        MapEntry(L10n.get(context, 'csTrust'), s.scoreTrust!),
      if (s.scoreEngagement != null)
        MapEntry(L10n.get(context, 'csEngagement'), s.scoreEngagement!),
      if (s.scoreConsistency != null)
        MapEntry(L10n.get(context, 'csConsistency'), s.scoreConsistency!),
    ];
    final chips = <String>[...s.platforms, ...s.contentFocus];
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: AppRadius.rMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sc in scores)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(sc.key, style: AppType.caption)),
                  Text('${sc.value}/5',
                      style: AppType.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.rPill,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(c, style: AppType.caption),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
