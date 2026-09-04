import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:presentation_capture/l10n/app_strings.dart';
import 'package:presentation_capture/main.dart';
import 'package:presentation_capture/pages/login_page.dart';
import 'package:presentation_capture/pages/settings_page.dart';
import 'package:presentation_capture/services/auth_service.dart';

Widget localized(Widget child, {String languageCode = 'en'}) => AppStringsScope(
  languageCode: languageCode,
  child: MaterialApp(home: child),
);

class _SignedOutAuthService extends AuthService {
  @override
  Future<bool> hasSession() async => false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('app startup resolves the session and shows login', (
    tester,
  ) async {
    await tester.pumpWidget(
      CaptureApp(
        authService: _SignedOutAuthService(),
        initialLanguageCode: 'en',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Presentation Capture'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('login screen exposes Google as the only sign-in path', (
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

    expect(find.text('Presentation Capture'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Email or username'), findsNothing);
    expect(find.text('Password'), findsNothing);
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
