import 'dart:io';

import 'package:flutter/services.dart';

class BackgroundUploadBridge {
  static const _channel = MethodChannel(
    'sg.edu.nus.presentation_capture/background_upload',
  );

  Future<bool> schedule({
    required String taskId,
    required String filePath,
    required Uri url,
    required Map<String, String> headers,
    required bool allowsCellular,
  }) async {
    if (!Platform.isIOS) return false;
    final scheduled = await _channel.invokeMethod<bool>('scheduleUpload', {
      'taskId': taskId,
      'filePath': filePath,
      'url': url.toString(),
      'headers': headers,
      'allowsCellular': allowsCellular,
    });
    return scheduled ?? false;
  }

  Future<Set<String>> activeTaskIds() async {
    if (!Platform.isIOS) return <String>{};
    final ids = await _channel.invokeListMethod<String>('activeTaskIds');
    return (ids ?? const <String>[]).toSet();
  }
}
