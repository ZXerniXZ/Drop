import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/audio_note.dart';
import 'api_url_resolver.dart';
import 'local_database_service.dart';
import 'supabase_auth_service.dart';

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

  Future<int> syncNotesFromServer() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return 0;

    try {
      final url = await ApiUrlResolver.resolveEndpoint('/notes');
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) return 0;

      final body = jsonDecode(response.body);
      if (body is! List) return 0;

      var inserted = 0;
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;

        final remoteId =
            item['note_id'] as String? ?? item['id'] as String?;
        if (remoteId == null || remoteId.isEmpty) continue;

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
}
