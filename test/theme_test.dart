// Faz 11 — Global light theme doğrulaması.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/design_system/design_system.dart';

void main() {
  test('Global V2 tema açık (light)', () {
    expect(buildFeedbackLightTheme().brightness, Brightness.light);
  });

  testWidgets('FeedbackScaffold gövdesi light tema sağlar', (tester) async {
    Brightness? b;
    await tester.pumpWidget(MaterialApp(
      home: FeedbackScaffold(
        body: Builder(builder: (c) {
          b = Theme.of(c).brightness;
          return const SizedBox();
        }),
      ),
    ));
    expect(b, Brightness.light);
  });

  testWidgets('Light tema scaffold zemini V2 background', (tester) async {
    Color? bg;
    await tester.pumpWidget(MaterialApp(
      theme: buildFeedbackLightTheme(),
      home: Builder(builder: (c) {
        bg = Theme.of(c).scaffoldBackgroundColor;
        return const SizedBox();
      }),
    ));
    expect(bg, AppColors.background);
  });
}
