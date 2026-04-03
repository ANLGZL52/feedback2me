import 'dart:math' as math;

import '../models/creator_intelligence_report.dart';
import 'creator_survey_aggregate.dart';

String _t(String a, String b) => a.trim().isNotEmpty ? a.trim() : b;

/// AI metin katmanını uygula; tüm sayısal alanlar ve ısı haritası [base] ile kalır.
CreatorIntelligenceReport mergeCreatorWithAiOverlay(
  CreatorIntelligenceReport base,
  CreatorIntelligenceReport? ai,
) {
  if (ai == null) return base;
  return CreatorIntelligenceReport(
    cover: CreatorCoverScores(
      communityPerception: base.cover.communityPerception,
      trust: base.cover.trust,
      contentClarity: base.cover.contentClarity,
      oneLiner: _t(ai.cover.oneLiner, base.cover.oneLiner),
      subScores: base.cover.subScores,
    ),
    executiveSummary: _t(ai.executiveSummary, base.executiveSummary),
    heatMap: base.heatMap,
    topDiagnoses: ai.topDiagnoses.length >= 2 ? ai.topDiagnoses : base.topDiagnoses,
    themeRows: ai.themeRows.length >= 4 ? ai.themeRows : base.themeRows,
    segments: ai.segments.length >= 3 ? ai.segments : base.segments,
    contentRecipe: ai.contentRecipe.length >= 3 ? ai.contentRecipe : base.contentRecipe,
    actionPlan: ActionPlanTiers(
      quickWins7d: ai.actionPlan.quickWins7d.isNotEmpty ? ai.actionPlan.quickWins7d : base.actionPlan.quickWins7d,
      medium30d: ai.actionPlan.medium30d.isNotEmpty ? ai.actionPlan.medium30d : base.actionPlan.medium30d,
      brand60d: ai.actionPlan.brand60d.isNotEmpty ? ai.actionPlan.brand60d : base.actionPlan.brand60d,
    ),
    replyTemplates: ai.replyTemplates.isNotEmpty ? ai.replyTemplates : base.replyTemplates,
    riskOpportunity: RiskOpportunityBlock(
      opportunity: _t(ai.riskOpportunity.opportunity, base.riskOpportunity.opportunity),
      risk: _t(ai.riskOpportunity.risk, base.riskOpportunity.risk),
    ),
    benchmarkLines: ai.benchmarkLines.isNotEmpty ? ai.benchmarkLines : base.benchmarkLines,
    reMeasureKpis: ai.reMeasureKpis.isNotEmpty ? ai.reMeasureKpis : base.reMeasureKpis,
    themeSignalTotal: base.themeSignalTotal,
    uniqueCommentCount: base.uniqueCommentCount,
    strategicDigest: _t(ai.strategicDigest ?? '', base.strategicDigest ?? ''),
    visualAndFormatInsight: _t(ai.visualAndFormatInsight, base.visualAndFormatInsight),
    comprehensiveCoachLetter: _t(ai.comprehensiveCoachLetter, base.comprehensiveCoachLetter),
  );
}

/// Ham istatistik + tema skorlarından creator raporu (AI yokken veya AI tabanı).
CreatorIntelligenceReport buildHeuristicCreatorReport({
  required int total,
  required int pos,
  required int neu,
  required int neg,
  required int posPct,
  required int neuPct,
  required int negPct,
  required Map<String, int> themeScores,
  required Map<String, int> themeNegWeight,
  required Map<String, int> relationMap,
  required List<MapEntry<String, int>> topThemes,
  required List<MapEntry<String, int>> weakest,
  required List<String> themeOrder,
  CreatorSurveyAggregate? surveyAggregate,
}) {
  final themeSignalTotal = themeScores.values.fold<int>(0, (a, b) => a + b);
  final maxT = math.max(
    1,
    themeScores.values.fold<int>(0, math.max),
  );

  int normTheme(String key) {
    final v = themeScores[key] ?? 0;
    return (100 * v / maxT).round().clamp(0, 100);
  }

  final trustT = normTheme('Güven ve samimiyet');
  final clarityT = ((normTheme('İletişim ve netlik') + normTheme('İçerik kalitesi')) / 2).round();
  final community = ((posPct + trustT + clarityT) / 3).round().clamp(0, 100);

  final subScores = <String, int>{
    'Güven': trustT,
    'Netlik': normTheme('İletişim ve netlik'),
    'Otorite': normTheme('İçerik kalitesi'),
    'Samimiyet': trustT,
    'Tutarlılık': normTheme('Tutarlılık ve süreklilik'),
    'Dönüşüm potansiyeli': (100 - (neuPct * 0.4).round()).clamp(35, 95),
  };

  final oneLiner = _oneLiner(posPct, neuPct, negPct, trustT, clarityT);

  final cover = CreatorCoverScores(
    communityPerception: community,
    trust: ((trustT * 0.55 + posPct * 0.45).round()).clamp(0, 100),
    contentClarity: clarityT,
    oneLiner: oneLiner,
    subScores: subScores,
  );

  final heat = AudienceHeatMapData(
    supportivePct: posPct,
    undecidedPct: neuPct,
    riskPct: negPct,
    supportiveHint: 'Büyütülebilir çekirdek topluluk — savunucuların ve tekrar eden olumlu sinyallerin kaynağı.',
    undecidedHint: 'Asıl fırsat alanı — net vaat ve format ile hızlıca olumluya kaydırılabilir.',
    riskHint: 'İtibar ve ton yönetimi gerektirir; şablonlu yanıt + net düzeltme ile risk düşer.',
  );

  final diagnoses = _topDiagnoses(weakest, topThemes, themeNegWeight, neuPct, negPct);

  final themeRows = <ThemeInsightRow>[];
  for (final name in themeOrder) {
    final sc = themeScores[name] ?? 0;
    final negW = themeNegWeight[name] ?? 0;
    final strength = sc >= maxT * 0.7
        ? 'Çok yüksek'
        : sc >= maxT * 0.35
            ? 'Yüksek'
            : sc > 0
                ? 'Orta'
                : 'Düşük';
    String dir;
    if (negW > sc * 0.35 && sc > 0) {
      dir = 'Karışık / baskın eleştiri';
    } else if (negW > 0) {
      dir = 'Nötr–olumsuz karışım';
    } else if (sc > 0) {
      dir = 'Olumlu eğilim';
    } else {
      dir = 'Sinyal düşük';
    }
    final meaning = sc == 0
        ? 'Bu başlıkta henüz güçlü örüntü yok; örneklem çeşitliliği artınca netleşir.'
        : (negW > sc ~/ 3
            ? 'Kitle bu başlığı yakından izliyor; beklenti ile sunum arasında sürtünme okunuyor.'
            : 'Bu eksen marka algın için tekrarlayan bir çerçeve oluşturuyor.');
    themeRows.add(
      ThemeInsightRow(
        theme: name,
        signalStrength: strength,
        sentimentDirection: dir,
        meaning: meaning,
      ),
    );
  }

  final segments = _segmentInsights(relationMap, total, pos, neg);

  final recipe = <ContentRecipeLine>[
    const ContentRecipeLine(
      percent: 40,
      label: 'Güven inşa eden içerik',
      detail: 'Yüzünü/kimliğini gösterdiğin, “neden buradasın?” sorusuna yanıt veren paylaşımlar.',
    ),
    const ContentRecipeLine(
      percent: 30,
      label: 'Otorite içerikleri',
      detail: 'Bilgi, mini rehber, analiz, örnek vaka — takipçinin “öğrendim” hissini güçlendir.',
    ),
    const ContentRecipeLine(
      percent: 20,
      label: 'Etkileşim içerikleri',
      detail: 'Soru, anket, karşılaştırma, yorum çağrısı — nötr kitlenin bağlanmasını artırır.',
    ),
    const ContentRecipeLine(
      percent: 10,
      label: 'Kişisel bağ',
      detail: 'Arka plan, süreç, samimi ama sınırlı paylaşım — güven ile dengeli.',
    ),
  ];

  final w0 = weakest.isNotEmpty ? weakest.first.key : (topThemes.isNotEmpty ? topThemes.first.key : 'İçerik kalitesi');

  final action = ActionPlanTiers(
    quickWins7d: [
      'Bio ve sabit içerikte hesap vaadini tek cümlede netleştir (kime, ne fayda).',
      'Son 10 içerikte kapak ve ilk cümle dilini tek şablonda hizala.',
      '“$w0” ile ilgili en sık iki soruyu yorumlardan çıkar; birine 60 sn’lik kısa cevap videosu çek.',
    ],
    medium30d: [
      'Haftalık 3 içeriklik tekrarlayan mini seri seç (aynı gün / aynı format).',
      'Yorumlardan en çok geçen 2 konuya özel 2’şer parçalık mini seri.',
      'CTA dilini tek sistemde topla (soru / yorum / kaydet).',
    ],
    brand60d: [
      'İçerik kategorilerini 3–4 ana başlıkta netleştir.',
      'Ton rehberi: cümle uzunluğu, emoji, mizah sınırı.',
      'Güven inşa eden düzenli seri (ör. haftalık şeffaflık turu).',
    ],
  );

  final replies = <ReplyTemplateItem>[
    const ReplyTemplateItem(
      title: 'Eleştiri yorumu',
      text:
          'Geri bildirimin için teşekkür ederim. Bu konuda daha net ve güçlü içerikler üretmek için çalışıyorum.',
    ),
    const ReplyTemplateItem(
      title: 'Kalite / netlik eleştirisi',
      text: 'Bunu not aldım. Özellikle bu başlıkta daha sade ve güçlü bir seri hazırlayacağım.',
    ),
    const ReplyTemplateItem(
      title: 'Destek yorumu',
      text: 'Burada olman çok değerli. En çok hangi konuda devam etmemi istersin?',
    ),
    const ReplyTemplateItem(
      title: 'Sert ton / risk',
      text:
          'Mesajını okudum. Tartışmayı büyütmeden, net bilgi ve tek somut adımla yanıtlıyorum: …',
    ),
  ];

  final opp = neuPct >= 45
      ? 'Kararsız kitlenin yüksek olması: doğru içerik düzeni ve net vaat ile hızlıca olumlu tarafa çekilebilir bir havuz.'
      : 'Olumlu çekirdek güçlü; vaadi büyütmek için tekrarlayan format ve seri ile ölçeklenebilir.';

  final risk = negPct > 18
      ? '"${weakest.isNotEmpty ? weakest.first.key : 'İçerik kalitesi'}" eleştirilerinin zamanla profesyonellik algısını aşağı çekme riski — küçük ama tutarlı düzeltmelerle kırılır.'
      : 'Belirgin bir itibar riski görünmüyor; tutarlılığı koruyarak büyümeye devam edilebilir.';

  final benchmarks = <String>[
    if (neuPct > posPct && neuPct > negPct)
      'Yüksek nötr oranı genelde “görünür ama henüz net konumlanmamış” profillerde görülür; vaat cümlesi netleşince dönüşür.',
    if (trustT > clarityT + 10)
      'Güven sinyali içerik netliğinden öndeyse marka kişiliği içerik sisteminden güçlü demektir; formatları hizalamak büyüme eşiğini aşmana yardım eder.',
    'Bu profil yapısı çoğu zaman büyüme eşiği döneminde görülür; ölçüm ve tekrar analiz kritik.',
  ];

  final reMeasure = <ReMeasureItem>[
    const ReMeasureItem(
      label: 'İçerik kalitesi algısı',
      hint: 'Tema sıralaması ve olumsuz ağırlık değişimi',
    ),
    const ReMeasureItem(
      label: 'Güven sinyali',
      hint: 'Güven teması ve olumlu oran birlikte',
    ),
    const ReMeasureItem(
      label: 'Olumsuz yoğunluk',
      hint: 'Risk yüzdesi ve risk temasındaki pay',
    ),
    const ReMeasureItem(
      label: 'Kararsız → olumlu kayış',
      hint: 'Nötr ve olumlu yüzdelerin farkı',
    ),
    const ReMeasureItem(
      label: 'Kritik tema sırası',
      hint: 'En zayıf 3 tema başlığının değişimi',
    ),
  ];

  final exec = StringBuffer()
    ..writeln(
      '$total benzersiz yorum incelendi. Genel tablo, kitlenin seni tamamen reddetmediğini; ',
    )
    ..write(
      neuPct >= 40
          ? 'içerik vaadinin ve mesaj netliğinin daha görünür olmasını beklediğini gösteriyor. '
          : 'duygu dengesinin taşınabilir bir temel oluşturduğunu gösteriyor. ',
    )
    ..writeln(
      'En güçlü sinyal "${topThemes.isNotEmpty ? topThemes.first.key : '—'}", gelişim odağı "${weakest.isNotEmpty ? weakest.first.key : '—'}". '
      'Bu, büyüme için felaket değil; doğru önceliklendirme ile hızlı iyileşme potansiyeli taşır.',
    );

  final digest = StringBuffer()
    ..writeln('▸ Algı özeti')
    ..writeln(
      'Takipçiler seni "${trustT >= clarityT ? 'önce güvenilir' : 'önce içerik tarafında'}" okuyor; '
      'öncelik ${neuPct > 35 ? 'nötr kitlenin net vaat ile olumluya çekilmesi' : 'olumlu tabanı büyütüp zayıf temayı sadeleştirmek'}.',
    )
    ..writeln()
    ..writeln('▸ Stratejik öncelik')
    ..writeln(
      'Sonraki 14 günde tek bir alt başlıkta (ör. "$w0") standart seri ve aynı kapak dilini test et; ardından yeniden ölç.',
    );

  final execStr = exec.toString().trim();
  final digestStr = digest.toString().trim();
  final visualInsight = _heuristicVisualInsight(
    surveyAggregate,
    total,
    themeScores,
  );
  final coachLetter = _heuristicCoachLetter(
    total: total,
    posPct: posPct,
    neuPct: neuPct,
    negPct: negPct,
    execSummary: execStr,
    surveyAggregate: surveyAggregate,
    priorityTheme: w0,
  );

  return CreatorIntelligenceReport(
    cover: cover,
    executiveSummary: execStr,
    heatMap: heat,
    topDiagnoses: diagnoses,
    themeRows: themeRows,
    segments: segments,
    contentRecipe: recipe,
    actionPlan: action,
    replyTemplates: replies,
    riskOpportunity: RiskOpportunityBlock(opportunity: opp, risk: risk),
    benchmarkLines: benchmarks,
    reMeasureKpis: reMeasure,
    themeSignalTotal: themeSignalTotal,
    uniqueCommentCount: total,
    strategicDigest: digestStr,
    visualAndFormatInsight: visualInsight,
    comprehensiveCoachLetter: coachLetter,
  );
}

String _heuristicVisualInsight(
  CreatorSurveyAggregate? agg,
  int total,
  Map<String, int> themeScores,
) {
  final tech = themeScores['Teknik ve sunum'] ?? 0;
  final buf = StringBuffer();
  if (agg == null || agg.isEmpty) {
    buf.writeln(
      'Yapılandırılmış anket yanıtı henüz yok veya çok az; görsel ve format okuması ağırlıklı olarak yorum metinlerindeki '
      '(ses, görüntü, kurgu, ışık, kapak vb.) ifadelerle ve “Teknik ve sunum” tema sinyaliyle desteklenir. '
      'Video dosyası analiz edilmez; izleyici öznel geri bildirimi ve metin temaları kullanılır.',
    );
    if (tech > 0) {
      buf.writeln(
        'Metinlerde teknik/görsel tema tekrar ediyor: ilk kare, ses netliği ve kesme ritmini standartlaştırmak hızlı kazanım sağlar.',
      );
    }
    return buf.toString().trim();
  }

  buf.writeln(
    'Bu bölüm; izleyici anketlerindeki 1–5 üretim/netlik/güven/eğlence/tutarlılık ortalamaları ile platform ve “hangi içerik türünde daha iyi olabilir” '
    'önerilerinden türetilir. Görünür içerik (thumbnail, çerçeve, ışık, kurgu ritmi) hakkında doğrudan video analizi yok; izleyici algısı ve metin birlikte yorumlanır.',
  );
  buf.writeln();
  buf.writeln(agg.toPromptBlock());
  buf.writeln();
  buf.writeln(
    'Pratik odak: Kapak ve ilk 3 saniyede tek vaat; kesme uzunluğunu platforma göre ayarlamak '
    '(${agg.platformCounts.isEmpty ? '—' : agg.platformCounts.keys.take(2).join(', ')} öne çıkıyor). '
    'Üretim ortalaması ${agg.avgProduction != null ? '${agg.avgProduction!.toStringAsFixed(1)}/5' : '—'} ise bir sonraki adım genelde ses zemini + görüntü stabilitesi + altyazı okunabilirliğidir.',
  );
  return buf.toString().trim();
}

String _heuristicCoachLetter({
  required int total,
  required int posPct,
  required int neuPct,
  required int negPct,
  required String execSummary,
  required CreatorSurveyAggregate? surveyAggregate,
  required String priorityTheme,
}) {
  final buf = StringBuffer()
    ..writeln('Bu bölüm sana doğrudan hitap eder; $total yorumun birleşik fotoğrafıdır.')
    ..writeln()
    ..writeln(execSummary)
    ..writeln()
    ..writeln(
      'Ayrıntılı stratejik brifing ve ▸ bölümleri bu raporda “Stratejik özet” kartında; burada ise özet + yön veren bir kapanış.',
    );

  if (surveyAggregate != null && !surveyAggregate.isEmpty) {
    buf.writeln();
    buf.writeln(
      'Anket dolduran izleyiciler platform, sıklık ve “hangi içerik türünde daha iyi olabilir” önerileriyle sinyal verdi; '
      'bunu sadece sayı değil, içerik deneylerinin önceliği olarak kullan.',
    );
  }

  buf.writeln();
  buf.writeln(
    'Önce “$priorityTheme” ekseninde küçük ve ölçülebilir tek bir deney seç; 10–14 gün uygula; aynı linkle yeniden geri bildirim topla. '
    'Tablo: olumlu %$posPct · nötr %$neuPct · olumsuz %$negPct — bu bir sınav sonucu değil; bir harita.',
  );

  return buf.toString().trim();
}

String _oneLiner(int posPct, int neuPct, int negPct, int trustT, int clarityT) {
  if (negPct > 22 && clarityT < 55) {
    return 'Etkileşim var; dönüşüm yaratacak netlik ve içerik standardı öne çıkmalı.';
  }
  if (trustT > clarityT + 12) {
    return 'Güven yüksek, fakat içerik vaadi ve çerçeve dağınık algılanıyor.';
  }
  if (neuPct > 48) {
    return 'Takipçi seni izliyor ama henüz tam bağ kurmuş değil — nötr kitle ana fırsat.';
  }
  if (posPct > 35 && negPct < 15) {
    return 'Çekirdek olumlu taban güçlü; vaadi ve formatı hizalayarak ölçekle.';
  }
  return 'Profil büyüme eşiğinde; net vaat ve tekrarlayan format ile metrikleri kaydır.';
}

List<CriticalDiagnosis> _topDiagnoses(
  List<MapEntry<String, int>> weakest,
  List<MapEntry<String, int>> topThemes,
  Map<String, int> themeNegWeight,
  int neuPct,
  int negPct,
) {
  final out = <CriticalDiagnosis>[];
  final w = weakest.take(3).toList();
  for (var i = 0; i < w.length && out.length < 3; i++) {
    final e = w[i];
    final heavyNeg = (themeNegWeight[e.key] ?? 0) > (e.value * 0.25).ceil();
    out.add(
      CriticalDiagnosis(
        title: '${e.key} baskısı',
        detail: heavyNeg
            ? 'Bu başlıkta olumsuz ton birikimi görülüyor; hedef daha fazla içerik değil, aynı vaatte sunum ve format standardını yükseltmek.'
            : 'Bu eksen izleyicide tekrar ediyor; mesajı sadeleştirip tek bir vaat cümlesine bağlamak büyümeyi hızlandırır.',
      ),
    );
  }
  if (out.length < 3 && neuPct > 42) {
    out.add(
      CriticalDiagnosis(
        title: 'Kararsız kitle yüksek',
        detail:
            'Nötr çoğunluk “henüz ikna olmadım” demektir; ilk 3 saniye ve kapak dilinde tek vaat ile test yap.',
      ),
    );
  }
  if (out.length < 3 && topThemes.isNotEmpty) {
    out.add(
      CriticalDiagnosis(
        title: 'İçerik çerçevesi',
        detail:
            '“${topThemes.first.key}” en görünür eksen; tüm serilerde aynı sözü vermek profesyonellik algısını yükseltir.',
      ),
    );
  }
  return out.take(3).toList();
}

List<SegmentInsight> _segmentInsights(Map<String, int> relationMap, int total, int pos, int neg) {
  int g(String k) => relationMap[k] ?? 0;

  final ark = g('ARKADAŞ') + g('AİLE') + g('PARTNER');
  final tak = g('TAKİPÇİ');
  final isM = g('İŞ ARKADAŞI') + g('MÜŞTERİ');
  final bel = g('BELİRSİZ');

  String pct(int n) => total > 0 ? '${((100 * n) / total).round()}%' : '—';

  return [
    SegmentInsight(
      segmentName: 'Sadık çekirdek kitle',
      description:
          'Arkadaş / aile / partner kaynaklı yaklaşık ${pct(ark)} hacim. Savunur, tekrar gelir, içeriklerde görünür.',
      action: 'Topluluk CTA: sabit yorum + hikâyede “senin için” içerik oylaması.',
    ),
    SegmentInsight(
      segmentName: 'Sessiz izleyici',
      description: 'Takipçi segmenti ~${pct(tak)}. Tüketir; henüz güçlü bağlılık sinyali vermeyebilir.',
      action: 'İlk cümlede tek net soru + kaydet çağrısı; formatı her seferinde aynı tut.',
    ),
    SegmentInsight(
      segmentName: 'Eleştirel geliştirici kitle',
      description: 'İş / müşteri kaynaklı ~${pct(isM)}. Saldırıdan çok “daha iyisini bekliyorum” tonu.',
      action: 'Kısa teşekkür + tek düzeltme + somut tarih; savunma yazma.',
    ),
    SegmentInsight(
      segmentName: 'Riskli yorum grubu',
      description:
          'Belirsiz veya sert ton potansiyeli taşıyan kesim ~${pct(bel)} (tüm ilişkilerde olumsuz oran $neg / $total).',
      action: 'Yorum şablonu: teşekkür + net bilgi + tek adım; tartışmayı büyütme.',
    ),
  ];
}
