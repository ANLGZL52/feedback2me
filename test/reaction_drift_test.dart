// Public static sayfa (web_static/f.html) REACTIONS ile Flutter kDefaultReactions
// arasında drift olursa FAIL. Key/emoji/sentiment birebir eşleşmeli.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:feedback_to_me/config/feedback_reactions.dart';

void main() {
  test('web_static/f.html REACTIONS == kDefaultReactions (key/emoji/sentiment)',
      () {
    final file = File('web_static/f.html');
    expect(file.existsSync(), isTrue, reason: 'f.html bulunamadı');
    final html = file.readAsStringSync();

    final block = RegExp(r'REACTIONS\s*=\s*\[(.*?)\]', dotAll: true)
        .firstMatch(html)
        ?.group(1);
    expect(block, isNotNull, reason: 'REACTIONS dizisi bulunamadı');

    final re = RegExp(
        r"key:\s*'([^']+)'\s*,\s*emoji:\s*'([^']+)'\s*,\s*sentiment:\s*(-?\d+)");
    final matches = re.allMatches(block!).toList();

    expect(matches.length, kDefaultReactions.length,
        reason:
            'Static reaction sayısı (${matches.length}) ≠ kDefaultReactions (${kDefaultReactions.length})');

    for (var i = 0; i < kDefaultReactions.length; i++) {
      final r = kDefaultReactions[i];
      final m = matches[i];
      expect(m.group(1), r.key, reason: 'key drift @$i');
      expect(m.group(2), r.emoji, reason: 'emoji drift @$i (${r.key})');
      expect(int.parse(m.group(3)!), r.sentiment,
          reason: 'sentiment drift @$i (${r.key})');
    }
  });
}
