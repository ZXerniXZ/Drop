import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'web_session.dart';

class LegalLinks {
  LegalLinks._();

  static const privacy = 'https://app.drop-prj.xyz/privacy/';
  static const terms = 'https://app.drop-prj.xyz/terms/';

  static Future<bool> open(String url) async {
    try {
      if (kIsWeb) {
        WebSession.openExternal(url);
        return true;
      }
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
