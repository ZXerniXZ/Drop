import 'package:http/http.dart' as http;

import '../config/api_config.dart';

enum ServerStatus { checking, online, offline }

class ServerHealthService {
  ServerHealthService._();

  static Future<ServerStatus> checkHealth({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await http
          .head(Uri.parse(productionHealthUrl))
          .timeout(timeout);

      if (response.statusCode == 200) return ServerStatus.online;

      final getResponse = await http
          .get(Uri.parse(productionHealthUrl))
          .timeout(timeout);
      return getResponse.statusCode == 200
          ? ServerStatus.online
          : ServerStatus.offline;
    } catch (_) {
      return ServerStatus.offline;
    }
  }
}
