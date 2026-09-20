import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// XHR (default [http.Client] on web) buffers the whole body, so SSE never
/// streams. Fetch keeps the response as a true byte stream.
http.Client createHttpClient() {
  return FetchClient(mode: RequestMode.cors);
}
