// Faz 7 — Settings sunum bileşenleri testleri.
// SettingsScreen'in tamamı Firebase (authService/appData) gerektirir; burada
// yeniden kullanılabilir V2 bileşenlerini test ediyoruz (backend yok).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_to_me/design_system/design_system.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
      ),
    );

void main() {
  testWidgets('FeedbackSettingsTile başlık + alt metin gösterir',
      (tester) async {
    await tester.pumpWidget(_host(const FeedbackSettingsTile(
      icon: Icons.translate_rounded,
      title: 'Türkçe',
      subtitle: 'Dil',
    )));
    expect(find.text('Türkçe'), findsOneWidget);
    expect(find.text('Dil'), findsOneWidget);
  });

  testWidgets('FeedbackSettingsTile onTap tetiklenir', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(FeedbackSettingsTile(
      icon: Icons.logout_rounded,
      title: 'Çıkış Yap',
      danger: true,
      onTap: () => taps++,
    )));
    await tester.tap(find.text('Çıkış Yap'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('Seçili dil tile trailing check gösterir', (tester) async {
    await tester.pumpWidget(_host(const FeedbackSettingsTile(
      icon: Icons.translate_rounded,
      title: 'English',
      selected: true,
      trailing: Icon(Icons.check_circle_rounded),
    )));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('FeedbackSettingsSection başlık + çocuklar + ayraç', (tester) async {
    await tester.pumpWidget(_host(FeedbackSettingsSection(
      title: 'Hesap',
      children: const [
        FeedbackSettingsTile(icon: Icons.person, title: 'A'),
        FeedbackSettingsTile(icon: Icons.mail, title: 'B'),
      ],
    )));
    expect(find.text('HESAP'), findsOneWidget); // başlık upper-case
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget); // iki satır arası tek ayraç
  });
}
