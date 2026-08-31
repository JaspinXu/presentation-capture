import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_strings.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final languageCode = preferences.getString('languageCode') ?? 'en';
  runApp(
    CaptureApp(authService: AuthService(), initialLanguageCode: languageCode),
  );
}

class CaptureApp extends StatefulWidget {
  const CaptureApp({
    super.key,
    required this.authService,
    required this.initialLanguageCode,
  });

  final AuthService authService;
  final String initialLanguageCode;

  @override
  State<CaptureApp> createState() => _CaptureAppState();
}

class _CaptureAppState extends State<CaptureApp> {
  late Locale _locale = Locale(widget.initialLanguageCode);
  late Future<bool> _hasSession;

  @override
  void initState() {
    super.initState();
    _hasSession = widget.authService.hasSession();
  }

  void _refreshSession() {
    setState(() => _hasSession = widget.authService.hasSession());
  }

  Future<void> _setLocale(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('languageCode', languageCode);
    setState(() => _locale = Locale(languageCode));
  }

  @override
  Widget build(BuildContext context) {
    return AppStringsScope(
      languageCode: _locale.languageCode,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NUS Presentation Capture',
        locale: _locale,
        supportedLocales: const [Locale('en'), Locale('zh')],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003D7C)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: FutureBuilder<bool>(
          future: _hasSession,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.data!) {
              return HomePage(
                authService: widget.authService,
                languageCode: _locale.languageCode,
                onLanguageChanged: _setLocale,
                onSignedOut: _refreshSession,
              );
            }
            return LoginPage(
              authService: widget.authService,
              onSignedIn: _refreshSession,
              languageCode: _locale.languageCode,
              onLanguageChanged: _setLocale,
            );
          },
        ),
      ),
    );
  }
}
