import 'dart:math';

import '../models/feedback_entry.dart';

/// Test için yapay yorum metni + duygu + ilişki üretir (Firestore’a yazılmadan önce).
FeedbackEntry buildSyntheticFeedback({
  required String docId,
  required String linkId,
  required Random rnd,
  int index = 0,
}) {
  final moodRoll = rnd.nextInt(100);
  final int mood;
  if (moodRoll < 28) {
    mood = 1;
  } else if (moodRoll < 82) {
    mood = 0;
  } else {
    mood = -1;
  }

  const relations = <String>[
    'takipçi',
    'arkadaş',
    'iş arkadaşı',
    'müşteri',
    'aile',
    'partner',
    'Belirsiz',
  ];
  final relation = relations[rnd.nextInt(relations.length)];

  final text = _composeComment(rnd, mood, index);

  final createdAt = DateTime.now().subtract(
    Duration(
      minutes: rnd.nextInt(60 * 24 * 45),
      seconds: rnd.nextInt(60),
    ),
  );

  return FeedbackEntry(
    id: docId,
    linkId: linkId,
    relation: relation,
    mood: mood,
    textRaw: text,
    createdAt: createdAt,
  );
}

String _composeComment(Random rnd, int mood, int index) {
  const open = <String>[
    'İçeriklerini genelde ',
    'Paylaşımlarında ',
    'Son dönemde ',
    'Videolarında ',
    'Yazdıklarında ',
    'Hikâyelerinde ',
    'Canlı yayınlarda ',
    'Podcast tarafında ',
  ];
  const midPos = <String>[
    'faydalı ve net bir çizgi görüyorum; bilgi yoğunluğu güçlü.',
    'samimi bir ton var, güven veriyor.',
    'iletişim netleştikçe daha çok etkileşim alırsın gibi.',
    'içerik kalitesi gözle görülür şekilde artmış.',
    'teknik olarak ses ve görüntü dengesi iyi.',
    'tutarlı bir yayın ritmi oluşmuş.',
  ];
  const midNeu = <String>[
    'bazı kısımlar net değil; ana mesajı öne çıkarmak faydalı olur.',
    'ara ara tekrar eden temalar var; çeşitlendirme düşünülebilir.',
    'marka çizgisi oturuyor ama farklı formatlar denenebilir.',
    'etkileşim orta seviyede; CTA ve sorular güçlendirilebilir.',
    'hikâye akışı yer yer dağınık hissediliyor.',
  ];
  const midNeg = <String>[
    'bazı bölümlerde ton sert; yumuşatılmış iletişim daha iyi olur.',
    'içerik sıklığı düşük; istikrar artınca topluluk bağlanır.',
    'güven konusunda karışık sinyaller var; şeffaflık artırılabilir.',
    'teknik olarak ses kalitesi zayıf; mikrofon veya ortam iyileşmeli.',
    'empati kurarken bazen tek taraflı kalıyor; denge önemli.',
  ];
  const themes = <String>[
    'İçerik kalitesi, iletişim netliği, güven ve samimiyet, tutarlılık, '
        'teknik sunum, etkileşim, marka algısı ve topluluk bağlılığı açısından ',
    'Sosyal medya görünürlüğü, reel/story dengesi, hashtag stratejisi ve '
        'geri bildirim kültürü bağlamında ',
    'Kişilik enerjisi, motivasyon, özgüven ve dinleyiciyle kurulan empati '
        'eksperinde ',
  ];
  const close = <String>[
    ' Uzun vadede ölçümle karşılaştırmak faydalı olur.',
    ' Küçük deneylerle ilerlemek mantıklı.',
    ' Bu konuda iki haftalık odak denenebilir.',
    ' Tekrarlayan yorumları not almak stratejiyi netleştirir.',
    ' Genel olarak yapıcı bir geri bildirim olarak değerlendiriyorum.',
  ];

  final buf = StringBuffer()
    ..write(open[rnd.nextInt(open.length)])
    ..write(themes[rnd.nextInt(themes.length)]);

  if (mood == 1) {
    buf.write(midPos[rnd.nextInt(midPos.length)]);
  } else if (mood == -1) {
    buf.write(midNeg[rnd.nextInt(midNeg.length)]);
  } else {
    buf.write(midNeu[rnd.nextInt(midNeu.length)]);
  }

  buf.write(close[rnd.nextInt(close.length)]);
  buf.write(' (#$index)');

  var s = buf.toString();
  if (s.length < 40) {
    s += ' Daha detaylı düşününce içerik ve iletişim tarafında küçük iyileştirmeler fark ediliyor.';
  }
  return s;
}
