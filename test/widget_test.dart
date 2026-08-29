import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nus_presentation_capture/l10n/app_strings.dart';
import 'package:nus_presentation_capture/pages/login_page.dart';
import 'package:nus_presentation_capture/pages/settings_page.dart';
import 'package:nus_presentation_capture/services/auth_service.dart';

Widget localized(Widget child, {String languageCode = 'en'}) => AppStringsScope(
  languageCode: languageCode,
  child: MaterialApp(home: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('login screen exposes all supported sign-in paths', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(
        LoginPage(
          authService: AuthService(),
          onSignedIn: () {},
          languageCode: 'en',
          onLanguageChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('NUS Presentation Capture'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('http://localhost:8080'), findsOneWidget);
  });

  testWidgets('settings exposes 720p, 1080p, 4K and upload controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(SettingsPage(languageCode: 'en', onLanguageChanged: (_) {})),
    );
    await tester.pump();

    expect(find.text('720p (recommended)'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('4K (compatible devices)'), findsOneWidget);
    expect(find.text('Allow mobile data uploads'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
  });
}
