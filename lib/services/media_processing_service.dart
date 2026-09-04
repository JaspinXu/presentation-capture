import 'dart:io';

import 'package:flutter/services.dart';

class MediaProcessingService {
  static const _channel = MethodChannel(
    'com.jaspinxu.presentation_capture/media_processing',
  );

  Future<String> extractAudio({
    required String videoPath,
    required String outputPath,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Audio extraction is currently available on iOS');
    }
    final path = await _channel.invokeMethod<String>('extractAudio', {
      'videoPath': videoPath,
      'outputPath': outputPath,
    });
    if (path == null || path.isEmpty) {
      throw StateError('Audio extraction did not produce a file');
    }
    return path;
  }
}
