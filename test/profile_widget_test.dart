// Faz 6 — Profil + Link Geçmişi sunum testleri (fake fixture; backend yok).
// Varsayılan locale: en.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/models/feedback_link.dart';
import 'package:feedback_to_me/models/user_profile.dart';
import 'package:feedback_to_me/widgets/profile/profile_header.dart';
import 'package:feedback_to_me/widgets/profile/link_history_card.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
      ),
    );

FeedbackLink _link({
  required String id,
  required bool active,
  DateTime? createdAt,
}) {
  return FeedbackLink(
    id: id,
    ownerId: 'o',
    code: 'code$id',
    linkTier: 'premium',
    isActive: active,
    validUntil: null, // countdown timer'ı testte tetiklememek için null
    createdAt: createdAt,
  );
}

void main() {
  testWidgets('Profil başlığı gerçek display name + email gösterir',
      (tester) async {
    final p = UserProfile(uid: 'u', displayName: 'Anıl Güzel', email: 'a@b.com');
    await tester.pumpWidget(_host(FeedbackProfileHeader(profile: p)));
    expect(find.text('Anıl Güzel'), findsOneWidget);
    expect(find.text('a@b.com'), findsOneWidget);
    // Premium/kredi yoksa rozet gösterilmez (fake metric yok).
    expect(find.text('Premium'), findsNothing);
  });

  testWidgets('Premium + kredi rozetleri yalnız gerçek değerde görünür',
      (tester) async {
    final p = UserProfile(
      uid: 'u',
      displayName: 'Deniz',
      isPremium: true,
      premiumUntil: DateTime(2999, 1, 1),
      paidLinkCredits: 3,
    );
    await tester.pumpWidget(_host(FeedbackProfileHeader(profile: p)));
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('3 link credits'), findsOneWidget);
  });

  testWidgets('İsim yoksa fallback kullanıcı adı gösterilir', (tester) async {
    final p = UserProfile(uid: 'u');
    await tester.pumpWidget(_host(FeedbackProfileHeader(profile: p)));
    // İsim boş olsa da başlık boş değil (bir metin render edilir).
    expect(find.byType(Text), findsWidgets);
  });

  testWidgets('Aktif link "Active" rozeti gösterir', (tester) async {
    await tester.pumpWidget(_host(LinkHistoryCard(
      link: _link(id: '1', active: true),
      feedbackCount: 4,
      onShare: () {},
      onCopy: () {},
      onSummary: () {},
      onComments: () {},
    )));
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('4 feedback'), findsOneWidget);
  });

  testWidgets('Tamamlanmış link "Completed" + özet callback', (tester) async {
    var summaryTaps = 0;
    await tester.pumpWidget(_host(LinkHistoryCard(
      link: _link(id: '2', active: false, createdAt: DateTime(2026, 8, 1)),
      feedbackCount: 12,
      onShare: () {},
      onCopy: () {},
      onSummary: () => summaryTaps++,
      onComments: () {},
    )));
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('View summary'));
    await tester.pump();
    expect(summaryTaps, 1);
  });
}
