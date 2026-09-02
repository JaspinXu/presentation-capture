import 'package:flutter_test/flutter_test.dart';
import 'package:nus_presentation_capture/models/video_record.dart';

void main() {
  test('video record preserves the three-file upload bundle', () {
    final record = VideoRecord(
      id: 'video-id',
      localPath: '/recordings/video.mp4',
      recordedAt: DateTime.utc(2026, 8, 31),
      durationSeconds: 60,
      resolution: '1080p',
      fileSize: 100,
      sha256: 'video-hash',
      audioPath: '/audio/audio.wav',
      audioSize: 20,
      audioSha256: 'audio-hash',
      presentationPath: '/presentations/slides.pdf',
      presentationName: 'slides.pdf',
      presentationSize: 30,
      presentationSha256: 'presentation-hash',
      status: UploadStatus.waiting,
    );

    final restored = VideoRecord.fromMap(record.toMap());

    expect(restored.localPath, endsWith('.mp4'));
    expect(restored.audioPath, endsWith('.wav'));
    expect(restored.presentationName, 'slides.pdf');
    expect(restored.presentationSha256, 'presentation-hash');
  });
}
