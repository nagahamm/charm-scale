import "package:flutter/material.dart";

import "../services/auth_service.dart";
import "../services/signup_api.dart";
import "../theme.dart";

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _signupApi = SignupApiService();

  bool _isSignUp = false;
  bool _loading = false;
  bool _acceptingSignUp = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSignUpStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _signupApi.dispose();
    super.dispose();
  }

  /// 新規登録の受付可否(docs/requirements.md 3.5節)。確認できない場合は受付中として扱う。
  Future<void> _loadSignUpStatus() async {
    final accepting = await _signupApi.fetchAccepting();
    if (mounted) setState(() => _acceptingSignUp = accepting);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = "ログインに失敗しました。もう一度お試しください。");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;
    if (_isSignUp && !_acceptingSignUp) return;
    await _run(
      () => _isSignUp
          ? _auth.signUpWithEmail(email: email, password: password)
          : _auth.signInWithEmail(email: email, password: password),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "振り返り",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!_acceptingSignUp) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        "現在、新規登録の受付を停止しています。空きが出るまでお待ちください。"
                        "すでにアカウントをお持ちの方はログインできます。",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (!isSupabaseConfigured)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      "SUPABASE_URL / SUPABASE_ANON_KEY が未設定です。--dart-define で指定してビルドしてください。",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed:
                      _loading || !isSupabaseConfigured ? null : () => _run(_auth.signInWithGoogle),
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text("Googleで続ける"),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed:
                      _loading || !isSupabaseConfigured ? null : () => _run(_auth.signInWithApple),
                  icon: const Icon(Icons.apple),
                  label: const Text("Appleで続ける"),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text("または", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _emailController,
                  enabled: !_loading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "メールアドレス", border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _passwordController,
                  enabled: !_loading,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "パスワード", border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: const TextStyle(color: AppColors.primaryDark, fontSize: 12)),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _loading || !isSupabaseConfigured || (_isSignUp && !_acceptingSignUp)
                      ? null
                      : _submitEmail,
                  child: Text(_isSignUp ? "アカウントを作成" : "ログイン"),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _loading ? null : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp ? "アカウントをお持ちの方はこちら" : "初めての方はこちら"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
