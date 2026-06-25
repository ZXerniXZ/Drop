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

  /// Redirect OAuth — registrare in Supabase Dashboard → Auth → URL Configuration
  static const oauthRedirectUri = 'com.drop.plaudclone.drop://login-callback/';
}
