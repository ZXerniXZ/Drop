import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_url_resolver.dart';
import 'drop_api_headers.dart';
import 'file_download.dart';
import 'supabase_auth_service.dart';

class AccountDataException implements Exception {
  AccountDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountDataService {
  AccountDataService._();

  static final AccountDataService instance = AccountDataService._();

  Future<void> downloadExport() async {
    final response = await _send('GET', '/account/export');
    if (response.statusCode != 200) {
      throw AccountDataException(_message(response));
    }
    await saveDownloadedBytes(response.bodyBytes, 'drop-dati.zip');
  }

  Future<void> deleteAccount() async {
    final response = await _send('DELETE', '/account');
    if (response.statusCode != 200) {
      throw AccountDataException(_message(response));
    }
  }

  Future<http.Response> _send(String method, String path) async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) {
      throw AccountDataException('Utente non autenticato');
    }
    final url = Uri.parse(await ApiUrlResolver.resolveEndpoint(path));
    final headers = DropApiHeaders.auth(token);
    final client = http.Client();
    try {
      final request = http.Request(method, url)..headers.addAll(headers);
      final streamed = await client.send(request);
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  String _message(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {}
    return 'Operazione non riuscita (${response.statusCode})';
  }
}
