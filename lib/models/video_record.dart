enum UploadStatus { localOnly, waiting, uploading, uploaded, failed }

class VideoRecord {
  const VideoRecord({
    required this.id,
    required this.localPath,
    required this.recordedAt,
    required this.durationSeconds,
    required this.resolution,
    required this.fileSize,
    required this.sha256,
    required this.status,
    this.title = '',
    this.experimentId = '',
    this.participantId = '',
    this.notes = '',
    this.progress = 0,
  });

  final String id;
  final String localPath;
  final DateTime recordedAt;
  final int durationSeconds;
  final String resolution;
  final int fileSize;
  final String sha256;
  final UploadStatus status;
  final String title;
  final String experimentId;
  final String participantId;
  final String notes;
  final double progress;

  Map<String, Object?> toMap() => {
    'id': id,
    'local_path': localPath,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'duration_seconds': durationSeconds,
    'resolution': resolution,
    'file_size': fileSize,
    'sha256': sha256,
    'status': status.name,
    'title': title,
    'experiment_id': experimentId,
    'participant_id': participantId,
    'notes': notes,
    'progress': progress,
  };

  factory VideoRecord.fromMap(Map<String, Object?> map) => VideoRecord(
    id: map['id']! as String,
    localPath: map['local_path']! as String,
    recordedAt: DateTime.parse(map['recorded_at']! as String),
    durationSeconds: map['duration_seconds']! as int,
    resolution: map['resolution']! as String,
    fileSize: map['file_size']! as int,
    sha256: map['sha256']! as String,
    status: UploadStatus.values.byName(map['status']! as String),
    title: (map['title'] as String?) ?? '',
    experimentId: (map['experiment_id'] as String?) ?? '',
    participantId: (map['participant_id'] as String?) ?? '',
    notes: (map['notes'] as String?) ?? '',
    progress: ((map['progress'] as num?) ?? 0).toDouble(),
  );

  VideoRecord copyWith({UploadStatus? status, double? progress}) => VideoRecord(
    id: id,
    localPath: localPath,
    recordedAt: recordedAt,
    durationSeconds: durationSeconds,
    resolution: resolution,
    fileSize: fileSize,
    sha256: sha256,
    status: status ?? this.status,
    title: title,
    experimentId: experimentId,
    participantId: participantId,
    notes: notes,
    progress: progress ?? this.progress,
  );
}
