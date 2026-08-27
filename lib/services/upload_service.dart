import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_record.dart';
import 'app_database.dart';
import 'auth_service.dart';
import 'background_upload_bridge.dart';

class UploadService {
  UploadService({AuthService? authService})
    : _auth = authService ?? AuthService();

  static const int partSize = 8 * 1024 * 1024;
  final AuthService _auth;
  final BackgroundUploadBridge _bridge = BackgroundUploadBridge();

  Future<Uri> _uri(String path) async {
    final preferences = await SharedPreferences.getInstance();
    final serverUrl =
        preferences.getString('serverUrl') ?? 'http://localhost:8080';
    return Uri.parse('$serverUrl$path');
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _auth.token();
    return {
      if (token != null) 'authorization': 'Bearer $token',
      if (json) 'content-type': 'application/json',
    };
  }

  Future<void> enqueue(VideoRecord video) async {
    var working = video.copyWith(status: UploadStatus.uploading, progress: 0);
    await AppDatabase.instance.save(working);
    try {
      await _ensureRemoteVideo(working);
      final totalParts = (working.fileSize / partSize).ceil();
      await _initializeUpload(working, totalParts);
      final completed = await _completedParts(working.id);
      final partFiles = await _prepareMissingParts(
        working,
        totalParts,
        completed,
      );
      final activeTaskIds = await _bridge.activeTaskIds();
      final preferences = await SharedPreferences.getInstance();
      final allowsCellular = preferences.getBool('allowCellular') ?? true;
      var scheduledInBackground = false;
      for (final entry in partFiles.entries) {
        final partNumber = entry.key;
        final file = entry.value;
        final taskId = '${working.id}:$partNumber';
        if (activeTaskIds.contains(taskId)) {
          scheduledInBackground = true;
          continue;
        }
        final scheduled = await _bridge.schedule(
          taskId: taskId,
          filePath: file.path,
          url: await _uri('/api/videos/${working.id}/parts/$partNumber'),
          headers: await _headers(json: false),
          allowsCellular: allowsCellular,
        );
        if (scheduled) {
          scheduledInBackground = true;
        } else {
          await _uploadPartForeground(working.id, partNumber, file);
        }
      }
      if (!scheduledInBackground) {
        await _completeIfReady(working, totalParts);
      } else {
        final nowCompleted = await _completedParts(working.id);
        working = working.copyWith(progress: nowCompleted.length / totalParts);
        await AppDatabase.instance.save(working);
      }
    } catch (_) {
      await AppDatabase.instance.save(
        working.copyWith(status: UploadStatus.failed),
      );
      rethrow;
    }
  }

  Future<void> reconcile(VideoRecord video) async {
    if (video.status == UploadStatus.uploaded ||
        video.status == UploadStatus.localOnly) {
      return;
    }
    try {
      final totalParts = (video.fileSize / partSize).ceil();
      final completed = await _completedParts(video.id);
      if (completed.length == totalParts) {
        await _completeIfReady(video, totalParts);
      } else {
        await AppDatabase.instance.save(
          video.copyWith(
            status: UploadStatus.uploading,
            progress: completed.length / totalParts,
          ),
        );
        await enqueue(video);
      }
    } catch (_) {
      // Offline reconciliation is expected; keep the existing task for retry.
    }
  }

  Future<void> _ensureRemoteVideo(VideoRecord video) async {
    final response = await http.post(
      await _uri('/api/videos'),
      headers: await _headers(),
      body: jsonEncode({
        'id': video.id,
        'title': video.title,
        'experimentId': video.experimentId,
        'participantId': video.participantId,
        'notes': video.notes,
        'recordedAt': video.recordedAt.toUtc().toIso8601String(),
        'durationSeconds': video.durationSeconds,
        'resolution': video.resolution,
        'fileSize': video.fileSize,
        'sha256': video.sha256,
      }),
    );
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 409) {
      throw HttpException('Create video failed: ${response.statusCode}');
    }
  }

  Future<void> _initializeUpload(VideoRecord video, int totalParts) async {
    final response = await http.post(
      await _uri('/api/videos/${video.id}/upload/init'),
      headers: await _headers(),
      body: jsonEncode({'partSize': partSize, 'totalParts': totalParts}),
    );
    if (response.statusCode != 200) {
      throw HttpException('Initialize upload failed: ${response.statusCode}');
    }
  }

  Future<Set<int>> _completedParts(String videoId) async {
    final response = await http.get(
      await _uri('/api/videos/$videoId/parts'),
      headers: await _headers(json: false),
    );
    if (response.statusCode != 200) {
      throw HttpException('List parts failed: ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['completedParts'] as List<dynamic>).cast<int>().toSet();
  }

  Future<Map<int, File>> _prepareMissingParts(
    VideoRecord video,
    int totalParts,
    Set<int> completed,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'upload_parts', video.id));
    await directory.create(recursive: true);
    final source = await File(video.localPath).open();
    final result = <int, File>{};
    try {
      for (var part = 0; part < totalParts; part++) {
        if (completed.contains(part)) continue;
        final output = File(p.join(directory.path, 'part_$part'));
        if (!await output.exists()) {
          await source.setPosition(part * partSize);
          final remaining = video.fileSize - (part * partSize);
          final bytes = await source.read(
            remaining < partSize ? remaining : partSize,
          );
          await output.writeAsBytes(bytes, flush: true);
        }
        result[part] = output;
      }
    } finally {
      await source.close();
    }
    return result;
  }

  Future<void> _uploadPartForeground(
    String videoId,
    int partNumber,
    File file,
  ) async {
    final request = http.Request(
      'PUT',
      await _uri('/api/videos/$videoId/parts/$partNumber'),
    );
    request.headers.addAll(await _headers(json: false));
    request.headers['content-type'] = 'application/octet-stream';
    request.bodyBytes = await file.readAsBytes();
    final response = await request.send();
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw HttpException('Upload part failed: ${response.statusCode}');
    }
  }

  Future<void> _completeIfReady(VideoRecord video, int totalParts) async {
    final response = await http.post(
      await _uri('/api/videos/${video.id}/upload/complete'),
      headers: await _headers(),
      body: jsonEncode({'totalParts': totalParts, 'sha256': video.sha256}),
    );
    if (response.statusCode != 200) {
      throw HttpException('Complete upload failed: ${response.statusCode}');
    }
    await AppDatabase.instance.save(
      video.copyWith(status: UploadStatus.uploaded, progress: 1),
    );
    final support = await getApplicationSupportDirectory();
    final parts = Directory(p.join(support.path, 'upload_parts', video.id));
    if (await parts.exists()) await parts.delete(recursive: true);
  }
}
