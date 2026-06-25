import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/audio_note.dart';
import '../models/note_chat_message.dart';

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
      version: 5,
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
            analysis_status TEXT NOT NULL DEFAULT 'ready',
            structured_json TEXT NOT NULL DEFAULT '{}'
          )
        ''');
        await _createChatTable(db);
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
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE audio_notes ADD COLUMN structured_json TEXT NOT NULL DEFAULT '{}'",
          );
        }
        if (oldVersion < 5) {
          await _createChatTable(db);
        }
      },
    );
  }

  static Future<void> _createChatTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_chat_messages (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoning TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_note_id ON note_chat_messages(note_id)',
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

  Future<bool> noteExists(String id) async {
    final rows = await _database.query(
      'audio_notes',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markNoteOpened(String id) async {
    await _database.update(
      'audio_notes',
      {'is_new': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllAudioPaths() async {
    await _database.update('audio_notes', {'audio_path': ''});
  }

  Future<void> deleteNote(String id) async {
    await deleteChatMessagesForNote(id);
    await _database.delete(
      'audio_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<NoteChatMessage>> getChatMessages(String noteId) async {
    final rows = await _database.query(
      'note_chat_messages',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
    return rows.map(NoteChatMessage.fromMap).toList();
  }

  Future<void> saveChatMessage(NoteChatMessage message) async {
    await _database.insert(
      'note_chat_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteChatMessagesForNote(String noteId) async {
    await _database.delete(
      'note_chat_messages',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
  }
}
