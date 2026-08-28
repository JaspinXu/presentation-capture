import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/video_record.dart';
import '../models/upload_session.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final directory = await getDatabasesPath();
    _database = await openDatabase(
      p.join(directory, 'capture.db'),
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE videos(
            id TEXT PRIMARY KEY,
            local_path TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            resolution TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            status TEXT NOT NULL,
            title TEXT NOT NULL,
            experiment_id TEXT NOT NULL,
            participant_id TEXT NOT NULL,
            notes TEXT NOT NULL,
            progress REAL NOT NULL
          )
        ''');
        await _createUploadTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createUploadTables(database);
      },
    );
    return _database!;
  }

  Future<List<VideoRecord>> allVideos() async {
    final db = await database;
    final rows = await db.query('videos', orderBy: 'recorded_at DESC');
    return rows.map(VideoRecord.fromMap).toList();
  }

  Future<void> save(VideoRecord video) async {
    final db = await database;
    await db.insert(
      'videos',
      video.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.transaction((transaction) async {
      final sessions = await transaction.query(
        'upload_sessions',
        columns: ['id'],
        where: 'video_id = ?',
        whereArgs: [id],
      );
      for (final session in sessions) {
        await transaction.delete(
          'upload_parts',
          where: 'session_id = ?',
          whereArgs: [session['id']],
        );
      }
      await transaction.delete(
        'upload_sessions',
        where: 'video_id = ?',
        whereArgs: [id],
      );
      await transaction.delete('videos', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<void> _createUploadTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS upload_sessions(
        id TEXT PRIMARY KEY,
        video_id TEXT NOT NULL UNIQUE,
        state TEXT NOT NULL,
        part_size INTEGER NOT NULL,
        total_parts INTEGER NOT NULL,
        completed_parts INTEGER NOT NULL,
        source_size INTEGER NOT NULL,
        source_modified_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL,
        next_retry_at TEXT,
        last_error TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(video_id) REFERENCES videos(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS upload_parts(
        session_id TEXT NOT NULL,
        part_number INTEGER NOT NULL,
        offset_bytes INTEGER NOT NULL,
        length_bytes INTEGER NOT NULL,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL,
        temp_path TEXT,
        sha256 TEXT,
        last_error TEXT NOT NULL,
        PRIMARY KEY(session_id, part_number),
        FOREIGN KEY(session_id) REFERENCES upload_sessions(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS upload_parts_state_idx '
      'ON upload_parts(session_id, state, part_number)',
    );
  }

  Future<UploadSession?> uploadSessionForVideo(String videoId) async {
    final db = await database;
    final rows = await db.query(
      'upload_sessions',
      where: 'video_id = ?',
      whereArgs: [videoId],
      limit: 1,
    );
    return rows.isEmpty ? null : UploadSession.fromMap(rows.first);
  }

  Future<void> saveUploadSession(UploadSession session) async {
    final db = await database;
    await db.insert(
      'upload_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> planUpload(UploadSession session, List<UploadPart> parts) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.insert(
        'upload_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final part in parts) {
        await transaction.insert(
          'upload_parts',
          part.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<UploadPart>> uploadParts(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'upload_parts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'part_number ASC',
    );
    return rows.map(UploadPart.fromMap).toList();
  }

  Future<void> updateUploadPart(
    String sessionId,
    int partNumber, {
    required UploadPartState state,
    int? attempts,
    String? tempPath,
    String? sha256,
    String? lastError,
    bool clearTempPath = false,
  }) async {
    final db = await database;
    final values = <String, Object?>{'state': state.name};
    if (attempts != null) values['attempts'] = attempts;
    if (clearTempPath) {
      values['temp_path'] = null;
    } else if (tempPath != null) {
      values['temp_path'] = tempPath;
    }
    if (sha256 != null) values['sha256'] = sha256;
    if (lastError != null) values['last_error'] = lastError;
    await db.update(
      'upload_parts',
      values,
      where: 'session_id = ? AND part_number = ?',
      whereArgs: [sessionId, partNumber],
    );
  }

  Future<void> markServerParts(String sessionId, Set<int> completed) async {
    final db = await database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'upload_parts',
        columns: ['part_number', 'state'],
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      for (final row in rows) {
        final number = row['part_number']! as int;
        final current = UploadPartState.values.byName(row['state']! as String);
        final next = completed.contains(number)
            ? UploadPartState.uploaded
            : current == UploadPartState.uploaded
            ? UploadPartState.planned
            : current;
        await transaction.update(
          'upload_parts',
          {'state': next.name},
          where: 'session_id = ? AND part_number = ?',
          whereArgs: [sessionId, number],
        );
      }
    });
  }

  Future<void> reclaimOrphanedUploadParts(
    String sessionId,
    Set<int> activePartNumbers,
  ) async {
    final db = await database;
    final rows = await db.query(
      'upload_parts',
      columns: ['part_number', 'state'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    for (final row in rows) {
      final number = row['part_number']! as int;
      final state = UploadPartState.values.byName(row['state']! as String);
      if ((state == UploadPartState.inFlight ||
              state == UploadPartState.staged) &&
          !activePartNumbers.contains(number)) {
        await db.update(
          'upload_parts',
          {'state': UploadPartState.planned.name},
          where: 'session_id = ? AND part_number = ?',
          whereArgs: [sessionId, number],
        );
      }
    }
  }
}
