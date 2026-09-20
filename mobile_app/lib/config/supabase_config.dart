import 'package:flutter/foundation.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'YOUR_SUPABASE_URL',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  static const mobileOauthRedirectUri =
      'com.drop.plaudclone.drop://login-callback/';

  static const webProductionOrigin = 'https://app.drop-prj.xyz';

  /// Registrare in GOTRUE_URI_ALLOW_LIST (PWA, localhost, schema mobile).
  static String get oauthRedirectUri {
    if (kIsWeb) return Uri.base.origin;
    return mobileOauthRedirectUri;
  }
}
