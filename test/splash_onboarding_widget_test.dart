// Faz 9 — Splash + Onboarding sunum testleri (Firebase/SharedPreferences yok).
// Varsayılan locale: en. AppOnboarding flag'e dokunmaz (onFinished callback).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/widgets/app_onboarding.dart';
import 'package:feedback_to_me/widgets/splash/feedback_splash_view.dart';

void main() {
  testWidgets('Splash marka + loader gösterir', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FeedbackSplashView()));
    expect(find.text('Feedback2Me'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Splash showLoader:false → loader yok', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: FeedbackSplashView(showLoader: false)));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Onboarding ilk slide başlığı + Continue', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: AppOnboarding(onFinished: () {})));
    expect(find.text('See what people\nreally think.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
  });

  testWidgets('Skip → onFinished callback', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
        MaterialApp(home: AppOnboarding(onFinished: () => finished++)));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('Continue → sonraki slide (2. slide gövdesi)', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: AppOnboarding(onFinished: () {})));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create your feedback link and share it with anyone.'),
        findsOneWidget);
  });

  testWidgets('Dar ekranda ilk slide taşmadan render eder', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: AppOnboarding(onFinished: () {})));
    await tester.pump();
    expect(find.text('See what people\nreally think.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
