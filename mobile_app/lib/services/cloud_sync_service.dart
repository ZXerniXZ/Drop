import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/audio_note.dart';
import 'api_url_resolver.dart';
import 'drop_api_headers.dart';
import 'local_database_service.dart';
import 'supabase_auth_service.dart';

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

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

  Future<int> syncNotesFromServer() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return 0;

    try {
      await _retryPendingDeletes();

      final url = await ApiUrlResolver.resolveEndpoint('/notes');
      final response = await http.get(
        Uri.parse(url),
        headers: DropApiHeaders.auth(token),
      );

      if (response.statusCode != 200) return 0;

      final body = jsonDecode(response.body);
      if (body is! List) return 0;

      var inserted = 0;
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;

        final remoteId = _remoteNoteId(item);
        if (remoteId == null) continue;

        if (await LocalDatabaseService.instance.isNoteDeleted(remoteId)) {
          await deleteNoteOnServer(remoteId);
          continue;
        }

        if (await LocalDatabaseService.instance.noteExists(remoteId)) continue;

        await LocalDatabaseService.instance.saveNote(
          AudioNote.fromServerNote(item),
        );
        inserted++;
      }

      return inserted;
    } catch (_) {
      return 0;
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

String? _remoteNoteId(Map item) {
  final remoteId = item['note_id'] ?? item['id'];
  if (remoteId is! String || remoteId.isEmpty) return null;
  return remoteId;
}
