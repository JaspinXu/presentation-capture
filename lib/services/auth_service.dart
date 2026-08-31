import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static Future<void>? _googleInitialization;

  Future<bool> hasSession() async =>
      (await _storage.read(key: 'token')) != null;
  Future<String?> token() => _storage.read(key: 'token');

  Future<Uri> _endpoint(String path) async {
    final preferences = await SharedPreferences.getInstance();
    final serverUrl =
        preferences.getString('serverUrl') ?? 'http://localhost:8080';
    return Uri.parse('$serverUrl$path');
  }

  Future<bool> signInWithGoogle() async {
    try {
      const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
      const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
      _googleInitialization ??= GoogleSignIn.instance.initialize(
        clientId: iosClientId.isEmpty ? null : iosClientId,
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      );
      await _googleInitialization;
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return false;
      return await _exchange('/api/auth/social', {
        'provider': 'google',
        'idToken': idToken,
      });
    } catch (_) {
      return false;
    }
  }

  Future<bool> _exchange(String path, Map<String, Object?> body) async {
    try {
      final response = await http
          .post(
            await _endpoint(path),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      await _storage.write(key: 'token', value: payload['token'] as String);
      await _storage.write(key: 'userId', value: payload['userId'] as String);
      if (payload['email'] is String) {
        await _storage.write(key: 'email', value: payload['email'] as String);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google may not have been configured or initialized.
    }
    await _storage.deleteAll();
  }
}
