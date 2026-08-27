import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();

  Future<bool> hasSession() async =>
      (await _storage.read(key: 'token')) != null;
  Future<String?> token() => _storage.read(key: 'token');

  Future<bool> signIn(String account, String password) async {
    final preferences = await SharedPreferences.getInstance();
    final serverUrl =
        preferences.getString('serverUrl') ?? 'http://localhost:8080';
    try {
      final response = await http
          .post(
            Uri.parse('$serverUrl/api/login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'account': account, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      await _storage.write(key: 'token', value: payload['token'] as String);
      await _storage.write(key: 'userId', value: payload['userId'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() => _storage.deleteAll();
}
