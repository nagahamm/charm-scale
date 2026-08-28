import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "screens/home_screen.dart";
import "screens/sign_in_screen.dart";
import "services/auth_service.dart";
import "theme.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const CharmScaleApp());
}

class CharmScaleApp extends StatelessWidget {
  const CharmScaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "振り返り",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// ログイン状態に応じて SignInScreen / HomeScreen を出し分ける。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isSupabaseConfigured) return const SignInScreen();

    return StreamBuilder<AuthState>(
      stream: AuthService().onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
        return session == null ? const SignInScreen() : const HomeScreen();
      },
    );
  }
}
