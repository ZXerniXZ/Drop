import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/audio_note.dart';
import '../models/note_folder.dart';
import '../utils/note_library.dart';
import 'api_url_resolver.dart';
import 'drop_api_headers.dart';
import 'local_database_service.dart';
import 'supabase_auth_service.dart';

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

  Future<void> _pushTail = Future<void>.value();

  /// Id delle note dell'account corrente. Null se il server non risponde:
  /// in quel caso non si deve buttare la cache locale.
  Future<Set<String>?> fetchRemoteNoteIds() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return null;

    try {
      final url = await ApiUrlResolver.resolveEndpoint('/notes');
      final response = await http.get(
        Uri.parse(url),
        headers: DropApiHeaders.auth(token),
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! List) return null;

      final ids = <String>{};
      for (final item in body) {
        if (item is! Map) continue;
        final id = _remoteNoteId(item);
        if (id != null) ids.add(id);
      }
      return ids;
    } catch (_) {
      return null;
    }
  }

  /// True se note o cartelle locali sono cambiate.
  Future<bool> syncNotesFromServer() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return false;

    final db = LocalDatabaseService.instance;
    final beforeFolders = await db.getAllFolders();
    final beforeNotes = await db.getAllNotes();

    try {
      await _retryPendingDeletes();
      await pushLibraryOutbox();

      var remoteFolders = await _fetchFolderList(token);
      final firstNotes = await _fetchNoteList(token);
      if (firstNotes == null) return false;
      var remoteNotes = firstNotes;

      if (remoteFolders != null) {
        final ready = await db.isLibrarySyncReady();
        final serverHasOrganization = remoteFolders.isNotEmpty ||
            remoteNotes.any((item) => item['folder_assigned'] == true);
        if (!ready && !serverHasOrganization) {
          await _enqueueLocalOrganization();
          await pushLibraryOutbox();
          final refreshedFolders = await _fetchFolderList(token);
          final refreshedNotes = await _fetchNoteList(token);
          if (refreshedFolders == null || refreshedNotes == null) return false;
          remoteFolders = refreshedFolders;
          remoteNotes = refreshedNotes;
        }
        final pulledFolders = <NoteFolder>[];
        for (final item in remoteFolders) {
          final folder = _folderFromServer(item);
          if (folder != null) pulledFolders.add(folder);
        }
        await db.replaceFolders(pulledFolders);
        await _applyRemoteNoteFolders(remoteNotes);
        await _reapplyOutbox();
        if (!ready) await db.setLibrarySyncReady();
      }

      await _insertNewRemoteNotes(remoteNotes);
    } catch (_) {
      return false;
    }

    final afterFolders = await db.getAllFolders();
    final afterNotes = await db.getAllNotes();
    return !_sameFolders(beforeFolders, afterFolders) ||
        !_sameNotePlacement(beforeNotes, afterNotes);
  }

  Future<void> queueFolderUpsert(NoteFolder folder) async {
    final db = LocalDatabaseService.instance;
    await db.dropPendingFolderUpserts({folder.id});
    await db.enqueueLibraryOp(
      kind: 'upsert_folder',
      payload: jsonEncode({
        'id': folder.id,
        'name': folder.name,
        'parent_id': folder.parentId,
        'created_at': folder.createdAt.toUtc().toIso8601String(),
      }),
    );
    await pushLibraryOutbox();
  }

  Future<void> queueFolderDelete({
    required List<NoteFolder> folders,
    required String rootId,
    required String? destinationId,
    required List<String> movedNoteIds,
  }) async {
    final ids = folderSubtreeIds(folders, rootId);
    final db = LocalDatabaseService.instance;
    await db.dropPendingFolderUpserts(ids);
    await db.dropPendingPlacementsInFolders(ids);
    await db.enqueueLibraryOp(
      kind: 'delete_folder',
      payload: jsonEncode({'id': rootId}),
    );
    for (final noteId in movedNoteIds) {
      await db.dropPendingNotePlacements(noteId);
      await db.enqueueLibraryOp(
        kind: 'place_note',
        payload: jsonEncode({
          'note_id': noteId,
          'folder_id': destinationId,
        }),
      );
    }
    await pushLibraryOutbox();
  }

  Future<void> queueNotePlacement(String noteId, String? folderId) async {
    final db = LocalDatabaseService.instance;
    await db.dropPendingNotePlacements(noteId);
    await db.enqueueLibraryOp(
      kind: 'place_note',
      payload: jsonEncode({
        'note_id': noteId,
        'folder_id': folderId,
      }),
    );
    await pushLibraryOutbox();
  }

  Future<void> pushLibraryOutbox() {
    final run = _pushTail.then((_) => _drainOutbox());
    _pushTail = run.catchError((_) {});
    return run;
  }

  Future<void> _enqueueLocalOrganization() async {
    final db = LocalDatabaseService.instance;
    final folders = foldersParentsFirst(await db.getAllFolders());
    for (final folder in folders) {
      await db.dropPendingFolderUpserts({folder.id});
      await db.enqueueLibraryOp(
        kind: 'upsert_folder',
        payload: jsonEncode({
          'id': folder.id,
          'name': folder.name,
          'parent_id': folder.parentId,
          'created_at': folder.createdAt.toUtc().toIso8601String(),
        }),
      );
    }
    for (final note in await db.getAllNotes()) {
      final folderId = note.folderId;
      if (folderId == null || folderId.isEmpty) continue;
      await db.dropPendingNotePlacements(note.id);
      await db.enqueueLibraryOp(
        kind: 'place_note',
        payload: jsonEncode({
          'note_id': note.id,
          'folder_id': folderId,
        }),
      );
    }
  }

  Future<void> _applyRemoteNoteFolders(List<Map<String, dynamic>> notes) async {
    final db = LocalDatabaseService.instance;
    final pendingMoves = await _pendingPlacementNoteIds();
    for (final item in notes) {
      if (item['folder_assigned'] != true) continue;
      final noteId = _remoteNoteId(item);
      if (noteId == null || pendingMoves.contains(noteId)) continue;
      if (!await db.noteExists(noteId)) continue;
      final raw = item['folder_id'];
      final folderId = raw is String && raw.isNotEmpty ? raw : null;
      await db.setNoteFolderId(noteId, folderId);
    }
  }

  Future<void> _insertNewRemoteNotes(List<Map<String, dynamic>> notes) async {
    final db = LocalDatabaseService.instance;
    for (final item in notes) {
      final remoteId = _remoteNoteId(item);
      if (remoteId == null) continue;
      if (await db.isNoteDeleted(remoteId)) {
        await deleteNoteOnServer(remoteId);
        continue;
      }
      if (await db.noteExists(remoteId)) continue;
      await db.saveNote(AudioNote.fromServerNote(item));
    }
  }

  Future<void> _reapplyOutbox() async {
    final db = LocalDatabaseService.instance;
    var folders = await db.getAllFolders();
    for (final row in await db.pendingLibraryOps()) {
      final kind = row['kind'] as String?;
      final decoded = jsonDecode(row['payload'] as String);
      if (decoded is! Map) continue;
      final payload = decoded.cast<String, dynamic>();
      if (kind == 'upsert_folder') {
        final folder = _folderFromPayload(payload);
        if (folder == null) continue;
        await db.saveFolder(folder);
        folders = [
          for (final item in folders)
            if (item.id != folder.id) item,
          folder,
        ];
      } else if (kind == 'delete_folder') {
        final rootId = payload['id'];
        if (rootId is! String || rootId.isEmpty) continue;
        final ids = folderSubtreeIds(folders, rootId);
        String? destination;
        for (final folder in folders) {
          if (folder.id == rootId) destination = folder.parentId;
        }
        await db.deleteFolders(ids: ids, moveNotesTo: destination);
        folders = [
          for (final folder in folders)
            if (!ids.contains(folder.id)) folder,
        ];
      } else if (kind == 'place_note') {
        final noteId = payload['note_id'];
        if (noteId is! String || noteId.isEmpty) continue;
        final raw = payload['folder_id'];
        final folderId = raw is String && raw.isNotEmpty ? raw : null;
        await db.setNoteFolderId(noteId, folderId);
      }
    }
  }

  Future<Set<String>> _pendingPlacementNoteIds() async {
    final ids = <String>{};
    for (final row in await LocalDatabaseService.instance.pendingLibraryOps()) {
      if (row['kind'] != 'place_note') continue;
      final decoded = jsonDecode(row['payload'] as String);
      if (decoded is! Map) continue;
      final noteId = decoded['note_id'];
      if (noteId is String && noteId.isNotEmpty) ids.add(noteId);
    }
    return ids;
  }

  Future<List<Map<String, dynamic>>?> _fetchFolderList(String token) async {
    final url = await ApiUrlResolver.resolveEndpoint('/folders');
    final response = await http.get(
      Uri.parse(url),
      headers: DropApiHeaders.auth(token),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! List) return null;
    return [
      for (final item in body)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  Future<List<Map<String, dynamic>>?> _fetchNoteList(String token) async {
    final url = await ApiUrlResolver.resolveEndpoint('/notes');
    final response = await http.get(
      Uri.parse(url),
      headers: DropApiHeaders.auth(token),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! List) return null;
    return [
      for (final item in body)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  Future<void> _drainOutbox() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return;
    final db = LocalDatabaseService.instance;
    for (final row in await db.pendingLibraryOps()) {
      final seq = row['seq'];
      final kind = row['kind'];
      if (seq is! int || kind is! String) return;
      final decoded = jsonDecode(row['payload'] as String);
      if (decoded is! Map) {
        await db.removeLibraryOp(seq);
        continue;
      }
      final outcome = await _sendLibraryOp(
        token,
        kind,
        decoded.cast<String, dynamic>(),
      );
      if (outcome == _LibraryOpOutcome.remove) {
        await db.removeLibraryOp(seq);
        continue;
      }
      if (outcome == _LibraryOpOutcome.keep) continue;
      return;
    }
  }

  Future<_LibraryOpOutcome> _sendLibraryOp(
    String token,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (kind == 'upsert_folder') {
        final id = payload['id'];
        if (id is! String || id.isEmpty) return _LibraryOpOutcome.remove;
        final url = await ApiUrlResolver.resolveEndpoint('/folders/$id');
        final response = await http.put(
          Uri.parse(url),
          headers: DropApiHeaders.json(token),
          body: jsonEncode({
            'name': payload['name'],
            'parent_id': payload['parent_id'],
            'created_at': payload['created_at'],
          }),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return _LibraryOpOutcome.remove;
        }
        return _LibraryOpOutcome.stop;
      }
      if (kind == 'delete_folder') {
        final id = payload['id'];
        if (id is! String || id.isEmpty) return _LibraryOpOutcome.remove;
        final url = await ApiUrlResolver.resolveEndpoint('/folders/$id');
        final response = await http.delete(
          Uri.parse(url),
          headers: DropApiHeaders.auth(token),
        );
        if (response.statusCode == 404 ||
            (response.statusCode >= 200 && response.statusCode < 300)) {
          return _LibraryOpOutcome.remove;
        }
        return _LibraryOpOutcome.stop;
      }
      if (kind == 'place_note') {
        final noteId = payload['note_id'];
        if (noteId is! String || noteId.isEmpty) return _LibraryOpOutcome.remove;
        final url = await ApiUrlResolver.resolveEndpoint(
          '/notes/$noteId/folder',
        );
        final response = await http.patch(
          Uri.parse(url),
          headers: DropApiHeaders.json(token),
          body: jsonEncode({'folder_id': payload['folder_id']}),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return _LibraryOpOutcome.remove;
        }
        if (response.statusCode == 404) return _LibraryOpOutcome.keep;
        return _LibraryOpOutcome.stop;
      }
      return _LibraryOpOutcome.remove;
    } catch (_) {
      return _LibraryOpOutcome.stop;
    }
  }

  Future<void> deleteNoteOnServer(String noteId) async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return;

    try {
      final url = await ApiUrlResolver.resolveEndpoint('/notes/$noteId');
      final response = await http.delete(
        Uri.parse(url),
        headers: DropApiHeaders.auth(token),
      );
      if (response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 400 ||
          response.statusCode == 403) {
        await LocalDatabaseService.instance.confirmNoteDeleted(noteId);
      }
    } catch (_) {}
  }

  Future<void> _retryPendingDeletes() async {
    final pending = await LocalDatabaseService.instance.pendingDeletedNoteIds();
    for (final noteId in pending) {
      await deleteNoteOnServer(noteId);
    }
  }
}

enum _LibraryOpOutcome { remove, keep, stop }

NoteFolder? _folderFromServer(Map<String, dynamic> item) {
  final id = item['id'];
  final name = item['name'];
  final createdRaw = item['created_at'];
  if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
    return null;
  }
  final created = createdRaw is String ? DateTime.tryParse(createdRaw) : null;
  final parent = item['parent_id'];
  return NoteFolder(
    id: id,
    name: name,
    createdAt: created ?? DateTime.now(),
    parentId: parent is String && parent.isNotEmpty ? parent : null,
  );
}

NoteFolder? _folderFromPayload(Map<String, dynamic> payload) {
  final id = payload['id'];
  final name = payload['name'];
  if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
    return null;
  }
  final createdRaw = payload['created_at'];
  final created = createdRaw is String ? DateTime.tryParse(createdRaw) : null;
  final parent = payload['parent_id'];
  return NoteFolder(
    id: id,
    name: name,
    createdAt: created ?? DateTime.now(),
    parentId: parent is String && parent.isNotEmpty ? parent : null,
  );
}

bool _sameFolders(List<NoteFolder> before, List<NoteFolder> after) {
  if (before.length != after.length) return false;
  final left = [...before]..sort((a, b) => a.id.compareTo(b.id));
  final right = [...after]..sort((a, b) => a.id.compareTo(b.id));
  for (var i = 0; i < left.length; i++) {
    if (left[i].id != right[i].id ||
        left[i].name != right[i].name ||
        left[i].parentId != right[i].parentId) {
      return false;
    }
  }
  return true;
}

bool _sameNotePlacement(List<AudioNote> before, List<AudioNote> after) {
  if (before.length != after.length) return false;
  final right = {for (final note in after) note.id: note.folderId};
  if (right.length != after.length) return false;
  for (final note in before) {
    if (!right.containsKey(note.id) || right[note.id] != note.folderId) {
      return false;
    }
  }
  return true;
}

String? _remoteNoteId(Map item) {
  final remoteId = item['note_id'] ?? item['id'];
  if (remoteId is! String || remoteId.isEmpty) return null;
  return remoteId;
}
