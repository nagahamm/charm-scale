import "package:supabase_flutter/supabase_flutter.dart";

/// ビルド時に --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... を渡す。
const _supabaseUrl = String.fromEnvironment("SUPABASE_URL");
const _supabaseAnonKey = String.fromEnvironment("SUPABASE_ANON_KEY");

/// OAuth(Google/Apple)のリダイレクト先。iOS/Androidのディープリンク設定と対応させる。
const oauthRedirectUrl = "io.charmscale.app://login-callback";

bool get isSupabaseConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

Future<void> initSupabase() async {
  if (!isSupabaseConfigured) return;
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
}

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;

  /// バックエンドAPIへの Authorization ヘッダーに使う JWT。未ログイン・未設定なら null。
  String? get accessToken => isSupabaseConfigured ? currentSession?.accessToken : null;

  Future<void> signInWithEmail({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signUpWithEmail({required String email, required String password}) =>
      _client.auth.signUp(email: email, password: password);

  Future<void> signInWithGoogle() =>
      _client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: oauthRedirectUrl);

  Future<void> signInWithApple() =>
      _client.auth.signInWithOAuth(OAuthProvider.apple, redirectTo: oauthRedirectUrl);

  Future<void> signOut() => _client.auth.signOut();
}
