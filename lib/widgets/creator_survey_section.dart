import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/creator_survey.dart';

/// İçerik üreticisi için isteğe bağlı anket; [buildPayload] ile gönderim öncesi okunur.
class CreatorSurveySection extends StatefulWidget {
  const CreatorSurveySection({super.key});

  @override
  State<CreatorSurveySection> createState() => CreatorSurveySectionState();
}

class CreatorSurveySectionState extends State<CreatorSurveySection> {
  static const _famKeys = ['first_time', 'short', 'medium', 'long'];
  static const _platKeys = [
    'instagram',
    'tiktok',
    'youtube',
    'twitch',
    'x',
    'linkedin',
    'other',
  ];
  static const _freqKeys = ['rare', 'monthly', 'weekly', 'daily'];
  static const _focusKeys = [
    'education',
    'entertainment',
    'lifestyle',
    'tech',
    'business',
    'gaming',
    'creative',
    'arts',
  ];

  String? _familiarity;
  final Set<String> _platforms = {};
  String? _watchFrequency;
  final Set<String> _contentFocus = {};
  int? _scoreProduction;
  int? _scoreClarity;
  int? _scoreTrust;
  int? _scoreEngagement;
  int? _scoreConsistency;

  CreatorSurveyPayload? buildPayload() {
    final p = CreatorSurveyPayload(
      familiarity: _familiarity,
      platforms: _platforms.toList()..sort(),
      watchFrequency: _watchFrequency,
      contentFocus: _contentFocus.toList()..sort(),
      scoreProduction: _scoreProduction,
      scoreClarity: _scoreClarity,
      scoreTrust: _scoreTrust,
      scoreEngagement: _scoreEngagement,
      scoreConsistency: _scoreConsistency,
    );
    return p.isEffectivelyEmpty ? null : p;
  }

  String _l10n(BuildContext context, String key) => L10n.get(context, key);

  Widget _likertRow(
    BuildContext context,
    ThemeData theme,
    String labelKey,
    int? value,
    void Function(int?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n(context, labelKey),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var n = 1; n <= 5; n++)
                ChoiceChip(
                  label: Text('$n'),
                  selected: value == n,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onSelected: (sel) {
                    setState(() {
                      onChanged(sel ? n : null);
                    });
                  },
                ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  setState(() => onChanged(null));
                },
                child: Text(
                  _l10n(context, 'creatorSurveyScoreClear'),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        title: Text(
          _l10n(context, 'creatorSurveySectionTitle'),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _l10n(context, 'creatorSurveySectionSubtitle'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white60,
              height: 1.35,
            ),
          ),
        ),
        children: [
          Text(
            _l10n(context, 'creatorSurveyFamiliarityLabel'),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _famKeys.map((k) {
              return ChoiceChip(
                label: Text(_l10n(context, 'creatorSurveyFam_$k')),
                selected: _familiarity == k,
                onSelected: (v) {
                  setState(() => _familiarity = v ? k : null);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            _l10n(context, 'creatorSurveyPlatformsLabel'),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _platKeys.map((k) {
              final selected = _platforms.contains(k);
              return FilterChip(
                label: Text(_l10n(context, 'creatorSurveyPlat_$k')),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _platforms.add(k);
                    } else {
                      _platforms.remove(k);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            _l10n(context, 'creatorSurveyFrequencyLabel'),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _freqKeys.map((k) {
              return ChoiceChip(
                label: Text(_l10n(context, 'creatorSurveyFreq_$k')),
                selected: _watchFrequency == k,
                onSelected: (v) {
                  setState(() => _watchFrequency = v ? k : null);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            _l10n(context, 'creatorSurveyFocusLabel'),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            _l10n(context, 'creatorSurveyFocusHint'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _focusKeys.map((k) {
              final selected = _contentFocus.contains(k);
              return FilterChip(
                label: Text(_l10n(context, 'creatorSurveyFocus_$k')),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _contentFocus.add(k);
                    } else {
                      _contentFocus.remove(k);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            _l10n(context, 'creatorSurveyScoresTitle'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _l10n(context, 'creatorSurveyScoreScale'),
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white38),
          ),
          const SizedBox(height: 12),
          _likertRow(
            context,
            theme,
            'creatorSurveyScore_production',
            _scoreProduction,
            (v) => _scoreProduction = v,
          ),
          _likertRow(
            context,
            theme,
            'creatorSurveyScore_clarity',
            _scoreClarity,
            (v) => _scoreClarity = v,
          ),
          _likertRow(
            context,
            theme,
            'creatorSurveyScore_trust',
            _scoreTrust,
            (v) => _scoreTrust = v,
          ),
          _likertRow(
            context,
            theme,
            'creatorSurveyScore_engagement',
            _scoreEngagement,
            (v) => _scoreEngagement = v,
          ),
          _likertRow(
            context,
            theme,
            'creatorSurveyScore_consistency',
            _scoreConsistency,
            (v) => _scoreConsistency = v,
          ),
        ],
      ),
    );
  }
}

