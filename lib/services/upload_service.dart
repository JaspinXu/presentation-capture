import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/upload_session.dart';
import '../models/video_record.dart';
import 'app_database.dart';
import 'auth_service.dart';
import 'background_upload_bridge.dart';

class UploadService {
  UploadService({AuthService? authService})
    : _auth = authService ?? AuthService();

  static const int partSize = 16 * 1024 * 1024;
  static const int stagingWindow = 3;
  static const int maxPartAttempts = 15;
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

  Future<void> enqueue(VideoRecord video, {bool force = false}) async {
    final source = File(video.localPath);
    await _validateSource(video, source);
    var session = await _sessionFor(video, source);
    await AppDatabase.instance.save(
      video.copyWith(
        status: UploadStatus.uploading,
        progress: session.completedParts / session.totalParts,
      ),
    );
    try {
      await _ensureRemoteVideo(video);
      await _initializeUpload(video, session);
      session = await _reconcileServer(video, session);
      if (session.completedParts == session.totalParts) {
        await _complete(video, session);
        return;
      }
      await _scheduleWindow(video, session, force: force);
    } catch (error) {
      await _recordFailure(video, session, error);
      rethrow;
    }
  }

  Future<void> reconcile(VideoRecord video) async {
    if (video.status == UploadStatus.uploaded ||
        video.status == UploadStatus.localOnly) {
      return;
    }
    try {
      await _consumeNativeEvents();
      final session = await AppDatabase.instance.uploadSessionForVideo(
        video.id,
      );
      if (session?.nextRetryAt != null &&
          session!.nextRetryAt!.isAfter(DateTime.now())) {
        return;
      }
      await enqueue(video);
    } catch (_) {
      // Network loss and background transitions are normal. State remains durable.
    }
  }

  Future<UploadSession> _sessionFor(VideoRecord video, File source) async {
    final existing = await AppDatabase.instance.uploadSessionForVideo(video.id);
    if (existing != null) {
      final stat = await source.stat();
      if (stat.size != existing.sourceSize ||
          (stat.modified.millisecondsSinceEpoch -
                      existing.sourceModifiedAt.millisecondsSinceEpoch)
                  .abs() >
              1000) {
        throw const FileSystemException(
          'Source video changed after the upload session was created',
        );
      }
      return existing;
    }
    final stat = await source.stat();
    final totalParts = (video.fileSize / partSize).ceil();
    final now = DateTime.now();
    final session = UploadSession(
      id: video.id,
      videoId: video.id,
      state: UploadSessionState.queued,
      partSize: partSize,
      totalParts: totalParts,
      completedParts: 0,
      sourceSize: video.fileSize,
      sourceModifiedAt: stat.modified,
      retryCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    final parts = <UploadPart>[
      for (var number = 0; number < totalParts; number++)
        UploadPart(
          sessionId: session.id,
          partNumber: number,
          offset: number * partSize,
          length: min(partSize, video.fileSize - (number * partSize)),
          state: UploadPartState.planned,
        ),
    ];
    await AppDatabase.instance.planUpload(session, parts);
    return session;
  }

  Future<void> _validateSource(VideoRecord video, File source) async {
    if (!await source.exists()) {
      throw const FileSystemException('Source video is missing');
    }
    final length = await source.length();
    if (length <= 0) throw const FileSystemException('Source video is empty');
    if (length != video.fileSize) {
      throw const FileSystemException(
        'Source video size changed after recording',
      );
    }
  }

  Future<void> _consumeNativeEvents() async {
    for (final event in await _bridge.pendingEvents()) {
      if (event['type'] != 'completed') continue;
      final taskId = event['taskId'] as String? ?? '';
      final separator = taskId.lastIndexOf('#');
      if (separator < 1) continue;
      final sessionId = taskId.substring(0, separator);
      final partNumber = int.tryParse(taskId.substring(separator + 1));
      if (partNumber == null) continue;
      final statusCode = (event['statusCode'] as num?)?.toInt() ?? 0;
      final parts = await AppDatabase.instance.uploadParts(sessionId);
      final matches = parts.where((part) => part.partNumber == partNumber);
      if (matches.isEmpty) continue;
      final part = matches.first;
      if (statusCode >= 200 && statusCode < 300) {
        await _deleteTemp(part.tempPath);
        await AppDatabase.instance.updateUploadPart(
          sessionId,
          partNumber,
          state: UploadPartState.uploaded,
          clearTempPath: true,
          lastError: '',
        );
      } else {
        await _deleteTemp(part.tempPath);
        await AppDatabase.instance.updateUploadPart(
          sessionId,
          partNumber,
          state: UploadPartState.planned,
          attempts: part.attempts + 1,
          clearTempPath: true,
          lastError: event['error'] as String? ?? 'HTTP $statusCode',
        );
      }
    }
  }

  Future<UploadSession> _reconcileServer(
    VideoRecord video,
    UploadSession session,
  ) async {
    final completed = await _completedParts(video.id);
    await AppDatabase.instance.markServerParts(session.id, completed);
    final updated = session.copyWith(
      state: completed.length == session.totalParts
          ? UploadSessionState.finalizing
          : UploadSessionState.transferring,
      completedParts: completed.length,
      retryCount: completed.length > session.completedParts
          ? 0
          : session.retryCount,
      clearNextRetryAt: true,
      lastError: '',
    );
    await AppDatabase.instance.saveUploadSession(updated);
    await AppDatabase.instance.save(
      video.copyWith(
        status: UploadStatus.uploading,
        progress: completed.length / session.totalParts,
      ),
    );
    await _removeCompletedTemps(updated.id, completed);
    return updated;
  }

  Future<void> _scheduleWindow(
    VideoRecord video,
    UploadSession session, {
    bool force = false,
  }) async {
    if (Platform.isIOS) {
      final preferences = await SharedPreferences.getInstance();
      final started = await _bridge.startSession(
        sessionId: session.id,
        sourcePath: video.localPath,
        fileSize: session.sourceSize,
        partSize: session.partSize,
        totalParts: session.totalParts,
        partUrlTemplate: await _uri('/api/videos/${video.id}/parts/__PART__'),
        finalizeUrl: await _uri('/api/videos/${video.id}/upload/complete'),
        finalizeBody: jsonEncode({
          'uploadSessionId': session.id,
          'totalParts': session.totalParts,
          'sha256': video.sha256,
        }),
        headers: await _headers(json: false),
        allowsCellular: preferences.getBool('allowCellular') ?? true,
        resetFailed: force,
      );
      if (!started) {
        throw StateError('The iOS background upload session could not start');
      }
      return;
    }
    final active = await _bridge.activeTaskIds();
    final activeParts = active
        .where((id) => id.startsWith('${session.id}#'))
        .map((id) => int.tryParse(id.substring(id.lastIndexOf('#') + 1)))
        .whereType<int>()
        .toSet();
    await AppDatabase.instance.reclaimOrphanedUploadParts(
      session.id,
      activeParts,
    );
    var available = stagingWindow - activeParts.length;
    if (available <= 0) return;
    final parts = await AppDatabase.instance.uploadParts(session.id);
    for (final part in parts.where(
      (part) => part.state == UploadPartState.planned,
    )) {
      if (available <= 0) break;
      if (part.attempts >= maxPartAttempts) {
        throw StateError('Part ${part.partNumber} exceeded its retry limit');
      }
      final staged = await _stagePart(video, part);
      final taskId = '${session.id}#${part.partNumber}';
      final preferences = await SharedPreferences.getInstance();
      final scheduled = await _bridge.schedule(
        taskId: taskId,
        filePath: staged.tempPath!,
        url: await _uri('/api/videos/${video.id}/parts/${part.partNumber}'),
        headers: {
          ...await _headers(json: false),
          'x-part-sha256': staged.sha256!,
          'x-upload-session': session.id,
        },
        allowsCellular: preferences.getBool('allowCellular') ?? true,
      );
      if (scheduled) {
        await AppDatabase.instance.updateUploadPart(
          session.id,
          part.partNumber,
          state: UploadPartState.inFlight,
          attempts: part.attempts + 1,
          tempPath: staged.tempPath,
          sha256: staged.sha256,
        );
        available--;
      } else {
        await _uploadPartForeground(video.id, staged);
        await _deleteTemp(staged.tempPath);
        await AppDatabase.instance.updateUploadPart(
          session.id,
          part.partNumber,
          state: UploadPartState.uploaded,
          attempts: part.attempts + 1,
          clearTempPath: true,
          sha256: staged.sha256,
        );
      }
    }
    final refreshed = await _reconcileServer(video, session);
    if (refreshed.completedParts == refreshed.totalParts) {
      await _complete(video, refreshed);
    } else {
      await _scheduleWindow(video, refreshed, force: force);
    }
  }

  Future<UploadPart> _stagePart(VideoRecord video, UploadPart part) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'upload_parts', part.sessionId),
    );
    await directory.create(recursive: true);
    final output = File(p.join(directory.path, 'part_${part.partNumber}'));
    if (!await output.exists() || await output.length() != part.length) {
      final source = await File(video.localPath).open();
      try {
        await source.setPosition(part.offset);
        final bytes = await source.read(part.length);
        if (bytes.length != part.length) {
          throw const FileSystemException(
            'Could not stage complete upload part',
          );
        }
        await output.writeAsBytes(bytes, flush: true);
      } finally {
        await source.close();
      }
    }
    final digest = await sha256.bind(output.openRead()).first;
    await AppDatabase.instance.updateUploadPart(
      part.sessionId,
      part.partNumber,
      state: UploadPartState.staged,
      tempPath: output.path,
      sha256: digest.toString(),
    );
    return UploadPart(
      sessionId: part.sessionId,
      partNumber: part.partNumber,
      offset: part.offset,
      length: part.length,
      state: UploadPartState.staged,
      attempts: part.attempts,
      tempPath: output.path,
      sha256: digest.toString(),
    );
  }

  Future<void> _uploadPartForeground(String videoId, UploadPart part) async {
    final file = File(part.tempPath!);
    final request = http.StreamedRequest(
      'PUT',
      await _uri('/api/videos/$videoId/parts/${part.partNumber}'),
    );
    request.headers.addAll(await _headers(json: false));
    request.headers['content-type'] = 'application/octet-stream';
    request.headers['x-part-sha256'] = part.sha256!;
    request.contentLength = await file.length();
    final client = http.Client();
    final responseFuture = client.send(request);
    await request.sink.addStream(file.openRead());
    await request.sink.close();
    try {
      final response = await responseFuture;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Upload part failed: ${response.statusCode}');
      }
    } finally {
      client.close();
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
    if (![200, 201].contains(response.statusCode)) {
      throw HttpException('Create video failed: ${response.statusCode}');
    }
  }

  Future<void> _initializeUpload(
    VideoRecord video,
    UploadSession session,
  ) async {
    final response = await http.post(
      await _uri('/api/videos/${video.id}/upload/init'),
      headers: await _headers(),
      body: jsonEncode({
        'uploadSessionId': session.id,
        'partSize': session.partSize,
        'totalParts': session.totalParts,
        'fileSize': session.sourceSize,
      }),
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
    return (payload['completedParts'] as List<dynamic>)
        .map((value) => (value as num).toInt())
        .toSet();
  }

  Future<void> _complete(VideoRecord video, UploadSession session) async {
    final response = await http.post(
      await _uri('/api/videos/${video.id}/upload/complete'),
      headers: await _headers(),
      body: jsonEncode({
        'uploadSessionId': session.id,
        'totalParts': session.totalParts,
        'sha256': video.sha256,
      }),
    );
    if (response.statusCode != 200) {
      throw HttpException('Complete upload failed: ${response.statusCode}');
    }
    await AppDatabase.instance.saveUploadSession(
      session.copyWith(
        state: UploadSessionState.completed,
        completedParts: session.totalParts,
        clearNextRetryAt: true,
        lastError: '',
      ),
    );
    await AppDatabase.instance.save(
      video.copyWith(status: UploadStatus.uploaded, progress: 1),
    );
    await _deleteSessionTemps(session.id);
  }

  Future<void> _recordFailure(
    VideoRecord video,
    UploadSession session,
    Object error,
  ) async {
    final retries = session.retryCount + 1;
    final delaySeconds =
        min(300, pow(2, min(retries, 8)).toInt()) + Random().nextInt(4);
    final terminal =
        retries >= maxPartAttempts ||
        error is FileSystemException ||
        error is StateError;
    await AppDatabase.instance.saveUploadSession(
      session.copyWith(
        state: terminal
            ? UploadSessionState.failedTerminal
            : UploadSessionState.waitingRetry,
        retryCount: retries,
        nextRetryAt: terminal
            ? null
            : DateTime.now().add(Duration(seconds: delaySeconds)),
        lastError: error.toString(),
      ),
    );
    await AppDatabase.instance.save(
      video.copyWith(status: UploadStatus.failed),
    );
  }

  Future<void> _removeCompletedTemps(
    String sessionId,
    Set<int> completed,
  ) async {
    final parts = await AppDatabase.instance.uploadParts(sessionId);
    for (final part in parts.where(
      (part) => completed.contains(part.partNumber),
    )) {
      await _deleteTemp(part.tempPath);
      await AppDatabase.instance.updateUploadPart(
        sessionId,
        part.partNumber,
        state: UploadPartState.uploaded,
        clearTempPath: true,
      );
    }
  }

  Future<void> _deleteTemp(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> _deleteSessionTemps(String sessionId) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'upload_parts', sessionId),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
