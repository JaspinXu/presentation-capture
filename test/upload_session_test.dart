import 'package:flutter_test/flutter_test.dart';
import 'package:nus_presentation_capture/models/upload_session.dart';

void main() {
  test('upload session survives a SQLite map round trip', () {
    final createdAt = DateTime.utc(2026, 8, 28, 10);
    final session = UploadSession(
      id: 'session-id',
      videoId: 'video-id',
      assetType: 'audio',
      state: UploadSessionState.transferring,
      partSize: 16 * 1024 * 1024,
      totalParts: 8,
      completedParts: 3,
      sourceSize: 120000000,
      sourceModifiedAt: createdAt,
      retryCount: 2,
      nextRetryAt: createdAt.add(const Duration(seconds: 8)),
      lastError: 'timeout',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = UploadSession.fromMap(session.toMap());

    expect(restored.state, UploadSessionState.transferring);
    expect(restored.assetType, 'audio');
    expect(restored.completedParts, 3);
    expect(restored.partSize, 16 * 1024 * 1024);
    expect(restored.nextRetryAt, createdAt.add(const Duration(seconds: 8)));
  });

  test('part model preserves offsets and retry state', () {
    const part = UploadPart(
      sessionId: 'session-id',
      partNumber: 4,
      offset: 64 * 1024 * 1024,
      length: 1024,
      state: UploadPartState.inFlight,
      attempts: 3,
      tempPath: '/tmp/part_4',
      sha256: 'abc',
    );

    final restored = UploadPart.fromMap(part.toMap());

    expect(restored.partNumber, 4);
    expect(restored.offset, 64 * 1024 * 1024);
    expect(restored.state, UploadPartState.inFlight);
    expect(restored.attempts, 3);
  });
}
