import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class WebSession {
  WebSession._();

  static JSObject? _deferredInstall;
  static bool _listeningForInstall = false;

  static bool get isIosSafari {
    final ua = web.window.navigator.userAgent;
    final isIos = ua.contains('iPhone') ||
        ua.contains('iPad') ||
        ua.contains('iPod') ||
        (ua.contains('Mac') && web.window.navigator.maxTouchPoints > 1);
    if (!isIos) return false;
    // Chrome/Firefox/Edge iOS are still WebKit, but the share-sheet install
    // flow is the Safari one. Exclude obvious third-party browsers.
    return !ua.contains('CriOS') && !ua.contains('FxiOS') && !ua.contains('EdgiOS');
  }

  static bool get isStandalone {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    if (web.window.matchMedia('(display-mode: fullscreen)').matches) {
      return true;
    }
    final standalone = web.window.navigator.getProperty('standalone'.toJS);
    return standalone == true.toJS;
  }

  static bool get shouldPromptHomeScreenInstall =>
      isIosSafari && !isStandalone;

  static void reload() {
    web.window.location.reload();
  }

  static void open(String url) {
    web.window.location.assign(url);
  }

  static void openExternal(String url) {
    web.window.open(url, '_blank');
  }

  static void listenForInstallPrompt() {
    if (_listeningForInstall) return;
    _listeningForInstall = true;
    web.window.addEventListener(
      'beforeinstallprompt',
      ((web.Event event) {
        event.preventDefault();
        _deferredInstall = event as JSObject;
      }).toJS,
    );
  }

  static bool get canPromptInstall => _deferredInstall != null;

  static Future<void> promptInstall() async {
    final prompt = _deferredInstall;
    if (prompt == null) return;
    prompt.callMethod('prompt'.toJS);
    _deferredInstall = null;
  }

  static void hideHtmlSplash() {
    web.document.getElementById('loading')?.remove();
  }
}
