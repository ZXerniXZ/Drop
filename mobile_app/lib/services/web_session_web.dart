import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class WebSession {
  WebSession._();

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

  static void hideHtmlSplash() {
    web.document.getElementById('loading')?.remove();
  }
}
