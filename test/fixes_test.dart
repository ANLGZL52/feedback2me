// Final MCP QA sonrası düzeltme testleri.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/design_system/design_system.dart';
import 'package:feedback_to_me/widgets/premium/premium_widgets.dart';

Widget _host(Widget c) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 120, child: c)));

void main() {
  testWidgets('MetricCard loading → spinner (sonsuz "…" yok)', (tester) async {
    await tester.pumpWidget(_host(const FeedbackMetricCard(
        value: '—', label: 'Feedback', loading: true, icon: Icons.forum)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(find.text('…'), findsNothing);
  });

  testWidgets('MetricCard hazır → değer gösterir, spinner yok', (tester) async {
    await tester.pumpWidget(_host(const FeedbackMetricCard(
        value: '42', label: 'Feedback', loading: false, icon: Icons.forum)));
    expect(find.text('42'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Kredi tekil metni (1 Link Credit) — PlanCompareCard render',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
      width: 300,
      child: PlanCompareCard(
        title: 'Premium Link',
        priceLabel: '1 Link Credit',
        highlighted: true,
        icon: Icons.workspace_premium_rounded,
        features: ['24 hours'],
      ),
    )));
    expect(find.text('1 Link Credit'), findsOneWidget);
    expect(find.text('1 Link Credits'), findsNothing);
  });
}
