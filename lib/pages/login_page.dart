import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.authService,
    required this.onSignedIn,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final AuthService authService;
  final VoidCallback onSignedIn;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _server = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      _server.text =
          preferences.getString('serverUrl') ?? 'http://localhost:8080';
    });
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _socialSignIn(Future<bool> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'serverUrl',
      _server.text.trim().replaceAll(RegExp(r'/$'), ''),
    );
    final success = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (success) {
      widget.onSignedIn();
    } else {
      setState(() => _error = context.strings.get('socialLoginFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    size: 72,
                    color: Color(0xFF003D7C),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.strings.get('appName'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: context.strings.get('serverUrl'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _socialSignIn(
                            widget.authService.signInWithGoogle,
                          ),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.g_mobiledata, size: 28),
                    label: Text(context.strings.get('continueGoogle')),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'en',
                        label: Text(context.strings.get('english')),
                      ),
                      ButtonSegment(
                        value: 'zh',
                        label: Text(context.strings.get('chinese')),
                      ),
                    ],
                    selected: {widget.languageCode},
                    onSelectionChanged: (value) =>
                        widget.onLanguageChanged(value.first),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
