import 'dart:io';

class ServerConfig {
  static String get defaultUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';

  static String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'/$'), '');
}
