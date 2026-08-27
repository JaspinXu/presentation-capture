import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/video_record.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final directory = await getDatabasesPath();
    _database = await openDatabase(
      p.join(directory, 'capture.db'),
      version: 1,
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
    await db.delete('videos', where: 'id = ?', whereArgs: [id]);
  }
}
