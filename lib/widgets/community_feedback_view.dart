import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/community_feedback_summary.dart';

const Color _kGold = Color(0xFFD4AF37);

String _moodEmoji(CommunityMood m) => switch (m) {
      CommunityMood.positive => '😍',
      CommunityMood.mixed => '👀',
      CommunityMood.negative => '🤔',
      CommunityMood.neutral => '🙂',
    };

/// FeedbackToMe 2.0 — Topluluk geri bildirimi: Crowd Score + Mood + En Sevilen
/// + En Çok Konuşulan + Hot Take + Gerçek Yorumlar + Reaction dağılımı.
class CommunityFeedbackView extends StatelessWidget {
  const CommunityFeedbackView({super.key, required this.summary});

  final CommunityFeedbackSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final en = L10n.languageCodeForApp(context) == 'en';
    String t(String tr, String enS) => en ? enS : tr;

    if (summary.isEmpty) {
      return Text(
        t('Henüz yorum yok. Linkini paylaşınca topluluk konuşmaya başlar 👀',
            'No feedback yet. Share your link and the crowd starts talking 👀'),
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: Colors.white70, height: 1.4),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScoreHeader(summary: summary),
        const SizedBox(height: 14),

        // TOPLULUK NE DİYOR? — mood + headline + kısa özet
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(t('TOPLULUK NE DİYOR?', 'WHAT THE CROWD SAYS')),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_moodEmoji(summary.mood),
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary.headline.isNotEmpty
                          ? summary.headline
                          : t('İlk izlenimler toplanıyor 🙂',
                              'First impressions are coming in 🙂'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (summary.shortSummary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  summary.shortSummary,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70, height: 1.45),
                ),
              ],
              if (summary.confidence == SummaryConfidence.low) ...[
                const SizedBox(height: 8),
                Text(
                  t('Not: Henüz az yorum var — kesin bir sonuç için biraz daha bekle.',
                      'Note: Only a little feedback so far — give it time for a clearer read.'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white54, height: 1.4),
                ),
              ],
            ],
          ),
        ),

        if (summary.mostLiked.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ChipsCard(
            label: t('🔥 EN ÇOK SEVİLEN', '🔥 MOST LOVED'),
            items: summary.mostLiked,
          ),
        ],

        if (summary.mostMentioned.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ChipsCard(
            label: t('👀 EN ÇOK KONUŞULAN', '👀 MOST MENTIONED'),
            items: summary.mostMentioned,
          ),
        ],

        if (summary.mixedOpinions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ChipsCard(
            label: t('⚖️ İKİYE BÖLÜNENLER', '⚖️ SPLIT OPINIONS'),
            items: summary.mixedOpinions,
          ),
        ],

        if (summary.hotTake.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(t('🌶️ HOT TAKE', '🌶️ HOT TAKE')),
                const SizedBox(height: 8),
                Text(
                  '“${summary.hotTake}”',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (summary.realComments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(t('💬 GERÇEK YORUMLAR', '💬 REAL COMMENTS')),
                const SizedBox(height: 10),
                ...summary.realComments.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Büyük Crowd Score + reaction dağılımı + duygu yüzdesi.
class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.summary});

  final CommunityFeedbackSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final en = L10n.languageCodeForApp(context) == 'en';
    String t(String tr, String enS) => en ? enS : tr;

    final score = summary.crowdScore;
    final reactions = summary.reactionCounts.entries.toList();

    return Card(
      color: _kGold.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            if (score != null)
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: score.toStringAsFixed(1),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: _kGold,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    TextSpan(
                      text: ' / 10',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (score != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  t('TOPLULUK SKORU', 'CROWD SCORE'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white38,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (reactions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 8,
                children: [
                  for (final r in reactions)
                    Text(
                      '${r.key} ${r.value}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              t('${summary.feedbackCount} kişi görüş bildirdi',
                  '${summary.feedbackCount} people shared their thoughts'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipsCard extends StatelessWidget {
  const _ChipsCard({required this.label, required this.items});

  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final it in items)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    it,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: _kGold,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
