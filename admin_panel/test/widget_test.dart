// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel/controllers/language_controller.dart';
import 'package:admin_panel/main.dart';

void main() {
  testWidgets('Admin app renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(languageController: LanguageController()));

    expect(find.text('Admin Login'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('Admin language toggle switches back and forth', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(languageController: LanguageController()));

    await tester.tap(find.text('Arabic'));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل دخول المسؤول'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Admin Login'), findsOneWidget);
  });
}
