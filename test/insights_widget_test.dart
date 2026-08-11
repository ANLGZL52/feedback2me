// Faz 5 — Topluluk içgörüsü sunum bileşenleri testleri.
// Fake fixture ile YALNIZCA presentation test edilir; production service/AI
// yeniden yazılmaz. Varsayılan locale: en.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/design_system/design_system.dart';
import 'package:feedback_to_me/models/community_feedback_summary.dart';
import 'package:feedback_to_me/models/feedback_entry.dart';
import 'package:feedback_to_me/widgets/insights/comment_card.dart';
import 'package:feedback_to_me/widgets/insights/community_summary_v2.dart';

CommunityFeedbackSummary _summary({
  double? crowdScore = 7.8,
  int feedbackCount = 12,
  int positive = 7,
  int neutral = 3,
  int negative = 2,
  List<String> mostLiked = const ['Clean design'],
  List<String> mostMentioned = const ['Pricing'],
  List<String> mixedOpinions = const [],
  String hotTake = '',
  String headline = 'People mostly liked it',
}) {
  return CommunityFeedbackSummary(
    mood: CommunityMood.positive,
    headline: headline,
    mostLiked: mostLiked,
    mostMentioned: mostMentioned,
    mixedOpinions: mixedOpinions,
    hotTake: hotTake,
    shortSummary: 'A short warm summary.',
    confidence: SummaryConfidence.high,
    crowdScore: crowdScore,
    feedbackCount: feedbackCount,
    positive: positive,
    neutral: neutral,
    negative: negative,
    reactionCounts: const {'🔥': 4},
    realComments: const [],
    aiUsed: true,
  );
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
      ),
    );

void main() {
  testWidgets('AI Summary gerçek feedbackCount gösterir', (tester) async {
    await tester.pumpWidget(_host(CommunitySummaryV2View(summary: _summary())));
    expect(find.text('Based on 12 real responses.'), findsOneWidget);
  });

  testWidgets('Boş liked section render edilmez, dolu ise edilir',
      (tester) async {
    await tester.pumpWidget(
        _host(CommunitySummaryV2View(summary: _summary(mostLiked: const []))));
    expect(find.text('What people love ❤️'), findsNothing);

    await tester.pumpWidget(_host(
        CommunitySummaryV2View(summary: _summary(mostLiked: const ['X']))));
    expect(find.text('What people love ❤️'), findsOneWidget);
  });

  testWidgets('Divided (mixedOpinions) boşsa render edilmez', (tester) async {
    await tester.pumpWidget(_host(
        CommunitySummaryV2View(summary: _summary(mixedOpinions: const []))));
    expect(find.text('Split opinions ⚖️'), findsNothing);
  });

  testWidgets('Hot take yalnız doluyken görünür', (tester) async {
    await tester.pumpWidget(_host(
        CommunitySummaryV2View(summary: _summary(hotTake: 'bold quote'))));
    expect(find.textContaining('bold quote'), findsOneWidget);
  });

  testWidgets('Loading state metni gösterir', (tester) async {
    await tester.pumpWidget(_host(const CommunitySummaryLoading()));
    expect(find.text('Summarizing what the crowd said…'), findsOneWidget);
  });

  testWidgets('Anonim yorum "Anonymous" gösterir', (tester) async {
    final e = FeedbackEntry(
        id: 'a', linkId: 'l', textRaw: 'Nice and simple.', mood: 1);
    await tester.pumpWidget(_host(FeedbackCommentCard(entry: e)));
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.text('Nice and simple.'), findsOneWidget);
  });

  testWidgets('İsimli yorum ismi gösterir', (tester) async {
    final e = FeedbackEntry(
        id: 'a',
        linkId: 'l',
        textRaw: 'Great work overall.',
        responderName: 'Deniz',
        mood: 1);
    await tester.pumpWidget(_host(FeedbackCommentCard(entry: e)));
    expect(find.text('Deniz'), findsOneWidget);
  });

  testWidgets('Error state retry callback çağırır', (tester) async {
    var retried = 0;
    await tester.pumpWidget(_host(FeedbackErrorState(
      message: 'err',
      retryLabel: 'Retry',
      onRetry: () => retried++,
    )));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
  });
}
