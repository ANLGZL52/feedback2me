// FeedbackToMe 2.0 — Reaction seti.
// Hızlı, eğlenceli, generic feedback. Gelecekte kategoriye göre farklı setler
// kullanılabilsin diye tek yerde tanımlı. Her reaction bir duyguya (-1/0/1)
// eşlenir; böylece eski `mood` alanı geriye dönük olarak türetilebilir.

/// Tek bir reaction seçeneği.
class FeedbackReaction {
  const FeedbackReaction({
    required this.key,
    required this.emoji,
    required this.labelTr,
    required this.labelEn,
    required this.sentiment, // -1 | 0 | 1
  });

  /// Kalıcı stabil anahtar (depolanan değer). Emoji değişse de bu sabit kalır.
  final String key;
  final String emoji;
  final String labelTr;
  final String labelEn;
  final int sentiment;

  String label(bool en) => en ? labelEn : labelTr;
}

/// Varsayılan generic reaction seti (brief ile uyumlu).
const List<FeedbackReaction> kDefaultReactions = [
  FeedbackReaction(key: 'fire', emoji: '🔥', labelTr: 'Çok iyi', labelEn: 'Fire', sentiment: 1),
  FeedbackReaction(key: 'love', emoji: '❤️', labelTr: 'Beğendim', labelEn: 'Love it', sentiment: 1),
  FeedbackReaction(key: 'wow', emoji: '😍', labelTr: 'Bayıldım', labelEn: 'Obsessed', sentiment: 1),
  FeedbackReaction(key: 'eyes', emoji: '👀', labelTr: 'Dikkat çekici', labelEn: 'Eye-catching', sentiment: 0),
  FeedbackReaction(key: 'hmm', emoji: '🤔', labelTr: 'Emin değilim', labelEn: 'Not sure', sentiment: 0),
  FeedbackReaction(key: 'fun', emoji: '😂', labelTr: 'Eğlenceli', labelEn: 'Fun', sentiment: 1),
  FeedbackReaction(key: 'meh', emoji: '🧐', labelTr: 'Bir şey eksik', labelEn: 'Missing something', sentiment: -1),
];

/// Anahtara göre reaction bul (bulunamazsa null).
FeedbackReaction? reactionByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final r in kDefaultReactions) {
    if (r.key == key) return r;
  }
  return null;
}

/// Reaction anahtarından duygu (-1/0/1) türet; bilinmiyorsa null.
int? sentimentForReaction(String? key) => reactionByKey(key)?.sentiment;

/// Reaction anahtarından emoji; bilinmiyorsa boş.
String emojiForReaction(String? key) => reactionByKey(key)?.emoji ?? '';
