// FeedbackToMe 2.0 — Reaction toplama servisi.
// Yorum kümesinden emoji reaction dağılımı ve duygu (pos/neu/neg) türetir.
// Reaction yoksa eski `mood` alanına düşer (geriye dönük).

import '../config/feedback_reactions.dart';
import '../models/feedback_entry.dart';

class ReactionTally {
  const ReactionTally({
    required this.byEmoji,
    required this.positive,
    required this.neutral,
    required this.negative,
    required this.total,
  });

  /// Emoji → adet ("🔥": 41). Yalnızca reaction seçilmiş yorumlar sayılır.
  final Map<String, int> byEmoji;

  /// Duygu sayımları (reaction sentiment; yoksa mood'dan).
  final int positive;
  final int neutral;
  final int negative;

  /// Toplam yorum sayısı (reaction olsun olmasın).
  final int total;

  int get totalReactions => byEmoji.values.fold<int>(0, (a, b) => a + b);

  static const empty = ReactionTally(
    byEmoji: {},
    positive: 0,
    neutral: 0,
    negative: 0,
    total: 0,
  );
}

class ReactionService {
  const ReactionService();

  /// Bir yorumun duygusu: önce reaction, yoksa mood, o da yoksa 0.
  static int sentimentOf(FeedbackEntry e) {
    final r = sentimentForReaction(e.reaction);
    if (r != null) return r;
    final m = e.mood;
    if (m == null) return 0;
    if (m > 0) return 1;
    if (m < 0) return -1;
    return 0;
  }

  /// Yorum kümesini reaction dağılımı + duygu sayımına indirger.
  ReactionTally tally(List<FeedbackEntry> entries) {
    if (entries.isEmpty) return ReactionTally.empty;
    final byEmoji = <String, int>{};
    var pos = 0, neu = 0, neg = 0;
    for (final e in entries) {
      final emoji = emojiForReaction(e.reaction);
      if (emoji.isNotEmpty) {
        byEmoji[emoji] = (byEmoji[emoji] ?? 0) + 1;
      }
      final s = sentimentOf(e);
      if (s > 0) {
        pos++;
      } else if (s < 0) {
        neg++;
      } else {
        neu++;
      }
    }
    // Adete göre azalan sırala.
    final sorted = Map.fromEntries(
      byEmoji.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return ReactionTally(
      byEmoji: sorted,
      positive: pos,
      neutral: neu,
      negative: neg,
      total: entries.length,
    );
  }
}
