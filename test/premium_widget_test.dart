// Faz 8 — Premium / Link Credit sunum testleri (fake fixture; IAP/backend yok).
// Varsayılan locale: en.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/widgets/premium/premium_widgets.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
      ),
    );

void main() {
  testWidgets('0 kredi → "0" + kredi-yok metni', (tester) async {
    await tester.pumpWidget(
        _host(const CreditBalanceCard(credits: 0, activePremium: false)));
    expect(find.text('0'), findsOneWidget);
    expect(find.text("You don't have any Premium Link credits yet."),
        findsOneWidget);
  });

  testWidgets('3 kredi → "3" + kredi ipucu', (tester) async {
    await tester.pumpWidget(
        _host(const CreditBalanceCard(credits: 3, activePremium: false)));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Each credit = 1 Premium Link'), findsOneWidget);
  });

  testWidgets('activePremium → "Premium access active" rozeti', (tester) async {
    await tester.pumpWidget(
        _host(const CreditBalanceCard(credits: 1, activePremium: true)));
    expect(find.text('Premium access active'), findsOneWidget);
  });

  testWidgets('Demo kartı demoUsed → "Used" rozeti', (tester) async {
    await tester.pumpWidget(_host(const PlanCompareCard(
      title: 'Demo',
      priceLabel: 'Free',
      highlighted: false,
      icon: Icons.science_rounded,
      badge: 'Used',
      features: ['10 minutes', '1 feedback'],
    )));
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('10 minutes'), findsOneWidget);
  });

  testWidgets('PurchaseCard localized fiyatı gösterir', (tester) async {
    await tester.pumpWidget(_host(const PurchaseCardV2(
      title: '1 Premium Link Credit',
      subtitle: 'Creates 1 Premium Link',
      price: '₺49,99',
      busy: false,
      onPressed: null,
    )));
    // Fiyat hem ayrı metinde hem CTA etiketinde geçer.
    expect(find.textContaining('₺49,99'), findsWidgets);
  });

  testWidgets('PurchaseCard busy → spinner (çift satın alma yok)',
      (tester) async {
    await tester.pumpWidget(_host(const PurchaseCardV2(
      title: 'x',
      subtitle: 'y',
      price: r'$1.99',
      busy: true,
      onPressed: null,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
