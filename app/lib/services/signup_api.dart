import "dart:convert";

import "package:http/http.dart" as http;

/// ビルド時に --dart-define=API_BASE_URL=https://your-site.netlify.app を渡す。
const _apiBase = String.fromEnvironment("API_BASE_URL");

/// レスポンスから受付可否を読む。エラー応答・壊れたJSON・想定外の形はすべて受付中として扱う
/// (fail-open。締め出しの事故を避ける、docs/design.md 4.1節)。
bool acceptingFromResponse(int statusCode, String body) {
  if (statusCode != 200) return true;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded["accepting"] != false : true;
  } catch (_) {
    return true;
  }
}

/// api/functions/signup.mjs との通信(新規登録の受付可否、docs/design.md 4.1節)。
class SignupApiService {
  final http.Client _client;

  SignupApiService({http.Client? client}) : _client = client ?? http.Client();

  /// 受付中かどうか。API_BASE_URL 未設定・通信失敗も受付中として扱う。
  Future<bool> fetchAccepting() async {
    if (_apiBase.isEmpty) return true;
    try {
      final response = await _client.get(Uri.parse("$_apiBase/api/signup-status"));
      return acceptingFromResponse(response.statusCode, response.body);
    } catch (_) {
      return true;
    }
  }

  void dispose() => _client.close();
}
