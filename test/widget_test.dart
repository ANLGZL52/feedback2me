// Feedback2Me V2 design-system widget testleri.
//
// Not: Uygulamanın tamamı (FeedbackToMeApp) Firebase.initializeApp gerektirir;
// test ortamında Firebase yoktur. Bu yüzden burada iş mantığına dokunmadan,
// yalnızca saf sunum bileşenlerini (design system) test ediyoruz.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/design_system/design_system.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('FeedbackPrimaryButton etiketi gösterir ve dokununca tetiklenir',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_host(
      FeedbackPrimaryButton(label: 'Gönder', onPressed: () => tapped++),
    ));

    expect(find.text('Gönder'), findsOneWidget);
    await tester.tap(find.text('Gönder'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('FeedbackPrimaryButton busy iken devre dışıdır (çift-submit yok)',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_host(
      FeedbackPrimaryButton(
          label: 'Gönder', busy: true, onPressed: () => tapped++),
    ));

    // Busy iken metin yerine spinner gösterilir.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FeedbackPrimaryButton));
    await tester.pump();
    expect(tapped, 0);
  });

  testWidgets('FeedbackPrimaryButton onPressed null iken tetiklenmez',
      (tester) async {
    await tester.pumpWidget(_host(
      const FeedbackPrimaryButton(label: 'Devam', onPressed: null),
    ));
    expect(find.text('Devam'), findsOneWidget);
    // Dokunma bir hata fırlatmamalı (disabled).
    await tester.tap(find.byType(FeedbackPrimaryButton));
    await tester.pump();
  });

  testWidgets('FeedbackStatusBadge etiketi gösterir', (tester) async {
    await tester.pumpWidget(_host(
      const FeedbackStatusBadge(label: 'Demo', tone: BadgeTone.neutral),
    ));
    expect(find.text('Demo'), findsOneWidget);
  });

  testWidgets('FeedbackTrustChip etiket + ikon gösterir', (tester) async {
    await tester.pumpWidget(_host(
      const FeedbackTrustChip(label: 'Anonim', icon: Icons.visibility_off),
    ));
    expect(find.text('Anonim'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });
}
