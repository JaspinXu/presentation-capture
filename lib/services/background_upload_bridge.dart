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
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    final scheduled = await _channel.invokeMethod<bool>('scheduleUpload', {
      'taskId': taskId,
      'filePath': filePath,
      'url': url.toString(),
      'headers': headers,
      'allowsCellular': allowsCellular,
    });
    return scheduled ?? false;
  }

  Future<bool> startSession({
    required String sessionId,
    required String sourcePath,
    required int fileSize,
    required int partSize,
    required int totalParts,
    required Uri partUrlTemplate,
    required Uri partsUrl,
    required Uri finalizeUrl,
    required String finalizeBody,
    required Map<String, String> headers,
    required bool allowsCellular,
    bool resetFailed = false,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    final started = await _channel.invokeMethod<bool>('startUploadSession', {
      'sessionId': sessionId,
      'sourcePath': sourcePath,
      'fileSize': fileSize,
      'partSize': partSize,
      'totalParts': totalParts,
      'partUrlTemplate': partUrlTemplate.toString(),
      'partsUrl': partsUrl.toString(),
      'finalizeUrl': finalizeUrl.toString(),
      'finalizeBody': finalizeBody,
      'headers': headers,
      'allowsCellular': allowsCellular,
      'resetFailed': resetFailed,
    });
    return started ?? false;
  }

  Future<Set<String>> activeTaskIds() async {
    if (!Platform.isIOS && !Platform.isAndroid) return <String>{};
    final ids = await _channel.invokeListMethod<String>('activeTaskIds');
    return (ids ?? const <String>[]).toSet();
  }

  Future<List<Map<String, Object?>>> pendingEvents() async {
    if (!Platform.isIOS && !Platform.isAndroid) return const [];
    final events = await _channel.invokeListMethod<Object?>('pendingEvents');
    return (events ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (event) => event.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  Future<int?> freeDiskBytes() async {
    if (!Platform.isIOS && !Platform.isAndroid) return null;
    return _channel.invokeMethod<int>('freeDiskBytes');
  }
}
