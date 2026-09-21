import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_url_resolver.dart';
import 'supabase_auth_service.dart';

class ServerQuotaExceeded implements Exception {
  ServerQuotaExceeded({
    required this.message,
    required this.usedSeconds,
    required this.limitSeconds,
    required this.remainingSeconds,
  });

  final String message;
  final int usedSeconds;
  final int limitSeconds;
  final int remainingSeconds;

  @override
  String toString() => message;
}

class ServerQuota {
  const ServerQuota({
    required this.usedSeconds,
    required this.limitSeconds,
    required this.remainingSeconds,
  });

  final int usedSeconds;
  final int limitSeconds;
  final int remainingSeconds;

  bool get isExhausted => remainingSeconds <= 0;

  bool wouldExceed(int incomingSeconds) =>
      usedSeconds + incomingSeconds > limitSeconds;

  String get remainingLabel => formatSeconds(remainingSeconds);

  String get usedLabel => formatSeconds(usedSeconds);

  String get limitLabel => formatSeconds(limitSeconds);

  static String formatSeconds(int seconds) {
    final clamped = seconds < 0 ? 0 : seconds;
    final hours = clamped ~/ 3600;
    final minutes = (clamped % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) return '$hours h $minutes min';
    if (hours > 0) return '$hours h';
    if (minutes > 0) return '$minutes min';
    return '0 min';
  }
}

class ServerQuotaService {
  ServerQuotaService._();

  static final ServerQuotaService instance = ServerQuotaService._();

  static const defaultMessage =
      'Hai esaurito le 2 ore di trascrizione incluse. Aggiungi una chiave OpenRouter in Account.';

  Future<ServerQuota?> fetch() async {
    final token = SupabaseAuthService.instance.currentAccessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final url = await ApiUrlResolver.resolveEndpoint('/usage/quota');
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return ServerQuota(
        usedSeconds: (body['used_seconds'] as num?)?.round() ?? 0,
        limitSeconds: (body['limit_seconds'] as num?)?.round() ?? 7200,
        remainingSeconds: (body['remaining_seconds'] as num?)?.round() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static ServerQuotaExceeded? parseError(http.Response response) {
    if (response.statusCode != 402) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final detail = body['detail'];
      if (detail is Map<String, dynamic> &&
          detail['code'] == 'server_quota_exceeded') {
        return ServerQuotaExceeded(
          message: detail['message'] as String? ?? defaultMessage,
          usedSeconds: (detail['used_seconds'] as num?)?.round() ?? 0,
          limitSeconds: (detail['limit_seconds'] as num?)?.round() ?? 7200,
          remainingSeconds: (detail['remaining_seconds'] as num?)?.round() ?? 0,
        );
      }
    } catch (_) {}
    return ServerQuotaExceeded(
      message: defaultMessage,
      usedSeconds: 7200,
      limitSeconds: 7200,
      remainingSeconds: 0,
    );
  }
}
