import 'http_text_impl.dart' as impl;
import 'http_text_response.dart';

export 'http_text_response.dart';

/// Reads the whole response body, then returns. Used on the web, where
/// incremental SSE often never reaches the page.
Future<HttpTextResponse> postText({
  required Uri url,
  required Map<String, String> headers,
  required String body,
  required Duration timeout,
}) {
  return impl.postTextImpl(
    url: url,
    headers: headers,
    body: body,
    timeout: timeout,
  );
}
