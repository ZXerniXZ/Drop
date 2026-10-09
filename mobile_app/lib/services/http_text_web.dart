import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'http_text_response.dart';

Future<HttpTextResponse> postTextImpl({
  required Uri url,
  required Map<String, String> headers,
  required String body,
  required Duration timeout,
}) {
  final xhr = web.XMLHttpRequest();
  final completer = Completer<HttpTextResponse>();

  void finish(HttpTextResponse response) {
    if (!completer.isCompleted) completer.complete(response);
  }

  void fail(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  xhr.open('POST', url.toString());
  xhr.timeout = timeout.inMilliseconds;
  for (final entry in headers.entries) {
    xhr.setRequestHeader(entry.key, entry.value);
  }

  xhr.onload = ((web.Event _) {
    finish(HttpTextResponse(statusCode: xhr.status, body: xhr.responseText));
  }).toJS;
  xhr.onerror = ((web.Event _) {
    fail(StateError('Richiesta di rete fallita'));
  }).toJS;
  xhr.ontimeout = ((web.Event _) {
    fail(TimeoutException('Tempo scaduto', timeout));
  }).toJS;

  xhr.send(body.toJS);
  return completer.future;
}
