enum UploadSessionState {
  queued,
  preparing,
  transferring,
  finalizing,
  completed,
  waitingRetry,
  paused,
  failedTerminal,
  cancelled,
}

enum UploadPartState { planned, staged, inFlight, uploaded }

class UploadSession {
  const UploadSession({
    required this.id,
    required this.videoId,
    required this.assetType,
    required this.state,
    required this.partSize,
    required this.totalParts,
    required this.completedParts,
    required this.sourceSize,
    required this.sourceModifiedAt,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    this.nextRetryAt,
    this.lastError = '',
  });

  final String id;
  final String videoId;
  final String assetType;
  final UploadSessionState state;
  final int partSize;
  final int totalParts;
  final int completedParts;
  final int sourceSize;
  final DateTime sourceModifiedAt;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'video_id': videoId,
    'asset_type': assetType,
    'state': state.name,
    'part_size': partSize,
    'total_parts': totalParts,
    'completed_parts': completedParts,
    'source_size': sourceSize,
    'source_modified_at': sourceModifiedAt.toUtc().toIso8601String(),
    'retry_count': retryCount,
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'last_error': lastError,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory UploadSession.fromMap(Map<String, Object?> map) => UploadSession(
    id: map['id']! as String,
    videoId: map['video_id']! as String,
    assetType: map['asset_type']! as String,
    state: UploadSessionState.values.byName(map['state']! as String),
    partSize: map['part_size']! as int,
    totalParts: map['total_parts']! as int,
    completedParts: map['completed_parts']! as int,
    sourceSize: map['source_size']! as int,
    sourceModifiedAt: DateTime.parse(map['source_modified_at']! as String),
    retryCount: map['retry_count']! as int,
    nextRetryAt: map['next_retry_at'] == null
        ? null
        : DateTime.parse(map['next_retry_at']! as String),
    lastError: (map['last_error'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );

  UploadSession copyWith({
    UploadSessionState? state,
    int? completedParts,
    int? retryCount,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    String? lastError,
  }) => UploadSession(
    id: id,
    videoId: videoId,
    assetType: assetType,
    state: state ?? this.state,
    partSize: partSize,
    totalParts: totalParts,
    completedParts: completedParts ?? this.completedParts,
    sourceSize: sourceSize,
    sourceModifiedAt: sourceModifiedAt,
    retryCount: retryCount ?? this.retryCount,
    nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
    lastError: lastError ?? this.lastError,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}

class UploadPart {
  const UploadPart({
    required this.sessionId,
    required this.partNumber,
    required this.offset,
    required this.length,
    required this.state,
    this.attempts = 0,
    this.tempPath,
    this.sha256,
    this.lastError = '',
  });

  final String sessionId;
  final int partNumber;
  final int offset;
  final int length;
  final UploadPartState state;
  final int attempts;
  final String? tempPath;
  final String? sha256;
  final String lastError;

  Map<String, Object?> toMap() => {
    'session_id': sessionId,
    'part_number': partNumber,
    'offset_bytes': offset,
    'length_bytes': length,
    'state': state.name,
    'attempts': attempts,
    'temp_path': tempPath,
    'sha256': sha256,
    'last_error': lastError,
  };

  factory UploadPart.fromMap(Map<String, Object?> map) => UploadPart(
    sessionId: map['session_id']! as String,
    partNumber: map['part_number']! as int,
    offset: map['offset_bytes']! as int,
    length: map['length_bytes']! as int,
    state: UploadPartState.values.byName(map['state']! as String),
    attempts: map['attempts']! as int,
    tempPath: map['temp_path'] as String?,
    sha256: map['sha256'] as String?,
    lastError: (map['last_error'] as String?) ?? '',
  );
}
