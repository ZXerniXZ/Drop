import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseAuthService {
  SupabaseAuthService._();

  static final SupabaseAuthService instance = SupabaseAuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isSignedIn => currentSession != null;

  String? get currentAccessToken => currentSession?.accessToken;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<Map<String, String>> authorizationHeaders() async {
    final token = currentAccessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Utente non autenticato');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signUp(email: email, password: password);
  }

  Future<void> signInWithMagicLink({required String email}) async {
    await _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: SupabaseConfig.oauthRedirectUri,
    );
  }

  Future<void> signInWithGoogle() => _signInWithOAuth(OAuthProvider.google);

  Future<void> signInWithGitHub() => _signInWithOAuth(OAuthProvider.github);

  Future<void> _signInWithOAuth(OAuthProvider provider) async {
    await _client.auth.signInWithOAuth(
      provider,
      redirectTo: SupabaseConfig.oauthRedirectUri,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}
