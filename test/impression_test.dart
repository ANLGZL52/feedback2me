// Personal Impression katmanı — model (parse/backward-compat) + UI testleri.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/models/community_feedback_summary.dart';
import 'package:feedback_to_me/widgets/insights/community_summary_v2.dart';

Widget _host(Widget c) => MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(child: SizedBox(width: 400, child: c))));

CommunityFeedbackSummary _base({
  FirstImpression? firstImpression,
  List<PersonImpression> personImpressions = const [],
  List<TraitItem> likedTraits = const [],
  List<GrowthArea> growthAreas = const [],
  List<String> threeWords = const [],
}) =>
    CommunityFeedbackSummary(
      mood: CommunityMood.positive,
      headline: 'h',
      mostLiked: const [],
      mostMentioned: const [],
      mixedOpinions: const [],
      hotTake: '',
      shortSummary: 's',
      confidence: SummaryConfidence.medium,
      crowdScore: 7.8,
      feedbackCount: 12,
      positive: 7,
      neutral: 3,
      negative: 2,
      reactionCounts: const {},
      realComments: const [],
      aiUsed: true,
      firstImpression: firstImpression,
      personImpressions: personImpressions,
      likedTraits: likedTraits,
      growthAreas: growthAreas,
      threeWords: threeWords,
    );

void main() {
  test('Zengin JSON → impression alanları parse edilir', () {
    final j = {
      'mood': 'positive',
      'feedbackCount': 12,
      'firstImpression': {'headline': 'Rahat ama mesafeli', 'description': 'x'},
      'personImpressions': [
        {'emoji': '😎', 'title': 'Rahat', 'description': 'd', 'tone': 'positive'}
      ],
      'likedTraits': [
        {'emoji': '✨', 'label': 'Doğallık'}
      ],
      'growthAreas': [
        {'emoji': '📸', 'title': 'Kamera açıları', 'description': 'd'}
      ],
      'threeWords': ['Rahat', 'Doğal', 'Mesafeli', 'Fazladan'],
    };
    final s = CommunityFeedbackSummary.fromJson(j);
    expect(s.firstImpression?.headline, 'Rahat ama mesafeli');
    expect(s.personImpressions.single.tone, 'positive');
    expect(s.likedTraits.single.label, 'Doğallık');
    expect(s.growthAreas.single.title, 'Kamera açıları');
    expect(s.threeWords.length, 3); // 3 ile sınırlı
    expect(s.hasImpressionLayer, isTrue);
  });

  test('Eski cache JSON (impression alanları yok) → crash yok, boş katman', () {
    final j = {'mood': 'neutral', 'feedbackCount': 5, 'headline': 'eski'};
    final s = CommunityFeedbackSummary.fromJson(j);
    expect(s.hasImpressionLayer, isFalse);
    expect(s.personImpressions, isEmpty);
    expect(s.firstImpression, isNull);
  });

  test('Malformed impression öğesi tüm parse\'ı bozmaz', () {
    final j = {
      'feedbackCount': 3,
      'personImpressions': [
        'not-an-object',
        {'title': 'Geçerli', 'tone': 'weirdvalue'}
      ],
      'likedTraits': [
        {'label': ''}
      ],
    };
    final s = CommunityFeedbackSummary.fromJson(j);
    expect(s.personImpressions.single.title, 'Geçerli');
    expect(s.personImpressions.single.tone, 'neutral'); // bilinmeyen → neutral
    expect(s.likedTraits, isEmpty); // boş label filtrelenir
  });

  testWidgets('UI: impression katmanı bölümleri render eder', (tester) async {
    await tester.pumpWidget(_host(CommunitySummaryV2View(
      summary: _base(
        firstImpression: const FirstImpression(headline: 'Rahat biri'),
        personImpressions: const [
          PersonImpression(emoji: '😎', title: 'Rahat izlenim', tone: 'positive')
        ],
        likedTraits: const [TraitItem(emoji: '✨', label: 'Doğallık')],
        threeWords: const ['Rahat', 'Doğal', 'Mesafeli'],
      ),
    )));
    expect(find.text('How people see you 👀'), findsOneWidget);
    expect(find.text('Rahat izlenim'), findsOneWidget);
    expect(find.text('You in three words 🧩'), findsOneWidget);
    expect(find.text('Mesafeli'), findsOneWidget);
  });

  testWidgets('UI: impression yoksa "How people see you" gösterilmez',
      (tester) async {
    await tester.pumpWidget(_host(CommunitySummaryV2View(summary: _base())));
    expect(find.text('How people see you 👀'), findsNothing);
  });
}
