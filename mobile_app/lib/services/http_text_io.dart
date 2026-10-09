import 'package:http/http.dart' as http;

import 'http_text_response.dart';

Future<HttpTextResponse> postTextImpl({
  required Uri url,
  required Map<String, String> headers,
  required String body,
  required Duration timeout,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('POST', url)
      ..headers.addAll(headers)
      ..body = body;
    final response = await client.send(request).timeout(timeout);
    final text = await response.stream.bytesToString().timeout(timeout);
    return HttpTextResponse(statusCode: response.statusCode, body: text);
  } finally {
    client.close();
  }
}
