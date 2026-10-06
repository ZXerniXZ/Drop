import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/audio_note.dart';
import '../models/note_chat_message.dart';
import '../models/note_folder.dart';

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
      version: 13,
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
            structured_json TEXT NOT NULL DEFAULT '{}',
            upload_session_id TEXT,
            uploaded_chunks INTEGER NOT NULL DEFAULT 0,
            transcript_segments TEXT NOT NULL DEFAULT '',
            analysis_phase TEXT,
            analysis_current INTEGER NOT NULL DEFAULT 0,
            analysis_total INTEGER NOT NULL DEFAULT 0,
            analysis_job_id TEXT,
            source_language TEXT,
            output_language TEXT,
            folder_id TEXT
          )
        ''');
        await _createChatTable(db);
        await _createDeletedNotesTable(db);
        await _createFoldersTable(db);
        await _createLibrarySyncTables(db);
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
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN upload_session_id TEXT',
          );
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN uploaded_chunks INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 7) {
          await db.execute(
            "ALTER TABLE audio_notes ADD COLUMN transcript_segments TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN analysis_phase TEXT',
          );
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN analysis_current INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN analysis_total INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 8) {
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN source_language TEXT',
          );
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN output_language TEXT',
          );
        }
        if (oldVersion < 9) {
          await _createDeletedNotesTable(db);
        }
        if (oldVersion < 10) {
          await db.execute(
            'ALTER TABLE audio_notes ADD COLUMN analysis_job_id TEXT',
          );
        }
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE audio_notes ADD COLUMN folder_id TEXT');
          await _createFoldersTable(db);
        }
        if (oldVersion >= 11 && oldVersion < 12) {
          await db.execute(
            'ALTER TABLE note_folders ADD COLUMN parent_id TEXT',
          );
        }
        if (oldVersion < 13) {
          await _createLibrarySyncTables(db);
        }
      },
    );
  }

  static Future<void> _createFoldersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        parent_id TEXT
      )
    ''');
  }

  static Future<void> _createLibrarySyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createDeletedNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_notes (
        id TEXT PRIMARY KEY,
        pending_remote INTEGER NOT NULL DEFAULT 1
      )
    ''');
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
    if (await isNoteDeleted(note.id)) return;
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

  Future<AudioNote?> getNote(String id) async {
    final rows = await _database.query(
      'audio_notes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AudioNote.fromMap(rows.first);
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

  /// Tiene l'id anche dopo la cancellazione locale, cosi' la sync non la
  /// riscarica. pending_remote resta 1 finche' il server non conferma.
  Future<void> markNoteDeleted(String id) async {
    await _database.insert(
      'deleted_notes',
      {'id': id, 'pending_remote': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isNoteDeleted(String id) async {
    final rows = await _database.query(
      'deleted_notes',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> confirmNoteDeleted(String id) async {
    await _database.update(
      'deleted_notes',
      {'pending_remote': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> pendingDeletedNoteIds() async {
    final rows = await _database.query(
      'deleted_notes',
      columns: ['id'],
      where: 'pending_remote = 1',
    );
    return [
      for (final row in rows)
        if (row['id'] is String) row['id'] as String,
    ];
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

  Future<List<NoteFolder>> getAllFolders() async {
    final rows = await _database.query(
      'note_folders',
      orderBy: 'created_at ASC',
    );
    return rows.map(NoteFolder.fromMap).toList();
  }

  Future<void> saveFolder(NoteFolder folder) async {
    await _database.insert(
      'note_folders',
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cancella le cartelle e sposta le loro note in [moveNotesTo].
  /// Null le riporta nella home.
  Future<void> deleteFolders({
    required Set<String> ids,
    required String? moveNotesTo,
  }) async {
    if (ids.isEmpty) return;
    final idList = ids.toList();
    final marks = List.filled(idList.length, '?').join(',');
    await _database.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE audio_notes SET folder_id = ? WHERE folder_id IN ($marks)',
        [moveNotesTo, ...idList],
      );
      await txn.rawDelete(
        'DELETE FROM note_folders WHERE id IN ($marks)',
        idList,
      );
    });
  }

  Future<void> replaceFolders(List<NoteFolder> folders) async {
    await _database.transaction((txn) async {
      await txn.delete('note_folders');
      for (final folder in folders) {
        await txn.insert(
          'note_folders',
          folder.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> setNoteFolderId(String noteId, String? folderId) async {
    await _database.update(
      'audio_notes',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  Future<void> enqueueLibraryOp({
    required String kind,
    required String payload,
  }) async {
    await _database.insert('library_outbox', {
      'kind': kind,
      'payload': payload,
    });
  }

  Future<void> dropPendingFolderUpserts(Set<String> ids) async {
    if (ids.isEmpty) return;
    final rows = await _database.query(
      'library_outbox',
      where: 'kind = ?',
      whereArgs: ['upsert_folder'],
    );
    for (final row in rows) {
      final payload = jsonDecode(row['payload'] as String);
      if (payload is Map && ids.contains(payload['id'])) {
        await _database.delete(
          'library_outbox',
          where: 'seq = ?',
          whereArgs: [row['seq']],
        );
      }
    }
  }

  Future<void> dropPendingPlacementsInFolders(Set<String> folderIds) async {
    if (folderIds.isEmpty) return;
    final rows = await _database.query(
      'library_outbox',
      where: 'kind = ?',
      whereArgs: ['place_note'],
    );
    for (final row in rows) {
      final payload = jsonDecode(row['payload'] as String);
      if (payload is Map && folderIds.contains(payload['folder_id'])) {
        await _database.delete(
          'library_outbox',
          where: 'seq = ?',
          whereArgs: [row['seq']],
        );
      }
    }
  }

  Future<void> dropPendingNotePlacements(String noteId) async {
    final rows = await _database.query(
      'library_outbox',
      where: 'kind = ?',
      whereArgs: ['place_note'],
    );
    for (final row in rows) {
      final payload = jsonDecode(row['payload'] as String);
      if (payload is Map && payload['note_id'] == noteId) {
        await _database.delete(
          'library_outbox',
          where: 'seq = ?',
          whereArgs: [row['seq']],
        );
      }
    }
  }

  Future<List<Map<String, Object?>>> pendingLibraryOps() async {
    return _database.query('library_outbox', orderBy: 'seq ASC');
  }

  Future<void> removeLibraryOp(int seq) async {
    await _database.delete(
      'library_outbox',
      where: 'seq = ?',
      whereArgs: [seq],
    );
  }

  Future<bool> isLibrarySyncReady() async {
    final rows = await _database.query(
      'library_meta',
      where: 'key = ?',
      whereArgs: ['synced'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return rows.first['value'] == '1';
  }

  Future<void> setLibrarySyncReady() async {
    await _database.insert(
      'library_meta',
      {'key': 'synced', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearLibraryOrganization() async {
    await _database.delete('note_folders');
    await _database.delete('library_outbox');
    await _database.delete('library_meta');
  }

  Future<void> deleteAllUserData() async {
    await _database.delete('note_chat_messages');
    await _database.delete('audio_notes');
    await _database.delete('deleted_notes');
    await _database.delete('note_folders');
    await _database.delete('library_outbox');
    await _database.delete('library_meta');
  }

  Future<void> clearDeletedNotes() async {
    await _database.delete('deleted_notes');
  }
}
