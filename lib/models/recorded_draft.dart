class RecordedDraft {
  const RecordedDraft({
    required this.id,
    required this.localPath,
    required this.recordedAt,
    required this.durationSeconds,
    required this.resolution,
  });

  final String id;
  final String localPath;
  final DateTime recordedAt;
  final int durationSeconds;
  final String resolution;
}
