import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/audio_note.dart';

class LocalDatabaseService {
  LocalDatabaseService._();

  static final LocalDatabaseService instance = LocalDatabaseService._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'drop_notes.db');

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE audio_notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            date_time TEXT NOT NULL,
            audio_path TEXT,
            transcription TEXT,
            summary TEXT,
            raw_transcription TEXT,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            is_new INTEGER NOT NULL DEFAULT 0,
            tag TEXT NOT NULL DEFAULT 'Diario',
            analysis_status TEXT NOT NULL DEFAULT 'ready'
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN is_new INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            "ALTER TABLE audio_notes ADD COLUMN tag TEXT NOT NULL DEFAULT 'Diario'",
          );
          await db.execute(
            "ALTER TABLE audio_notes ADD COLUMN analysis_status TEXT NOT NULL DEFAULT 'ready'",
          );
        }
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalDatabaseService not initialized. Call init() first.');
    }
    return db;
  }

  Future<void> saveNote(AudioNote note) async {
    await _database.insert(
      'audio_notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AudioNote>> getAllNotes() async {
    final rows = await _database.query(
      'audio_notes',
      orderBy: 'date_time DESC',
    );
    return rows.map(AudioNote.fromMap).toList();
  }

  Future<void> markNoteOpened(String id) async {
    await _database.update(
      'audio_notes',
      {'is_new': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteNote(String id) async {
    await _database.delete(
      'audio_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
