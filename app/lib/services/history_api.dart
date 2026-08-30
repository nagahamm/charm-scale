import "dart:convert";

import "package:http/http.dart" as http;

import "../models/analysis.dart";
import "../models/person.dart";
import "auth_service.dart";

/// ビルド時に --dart-define=API_BASE_URL=https://your-site.netlify.app を渡す。
const _apiBase = String.fromEnvironment("API_BASE_URL");

class HistoryApiException implements Exception {
  final String message;
  const HistoryApiException(this.message);

  @override
  String toString() => message;
}

/// api/functions/analyses.mjs との通信(Person(相手)のCRUD・履歴取得)。
class HistoryApiService {
  final http.Client _client;

  HistoryApiService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers() {
    final token = AuthService().accessToken;
    return {
      "content-type": "application/json; charset=utf-8",
      if (token != null) "authorization": "Bearer $token",
    };
  }

  Uri _uri(String resource, [Map<String, String> query = const {}]) =>
      Uri.parse("$_apiBase/api/analyses").replace(queryParameters: {"resource": resource, ...query});

  Future<T> _send<T>(Future<http.Response> Function() send, T Function(dynamic body) onOk) async {
    if (_apiBase.isEmpty) {
      throw const HistoryApiException("API_BASE_URL が未設定です。--dart-define=API_BASE_URL=... を指定してビルドしてください。");
    }
    final response = await send();
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode != 200) {
      final message = decoded is Map && decoded["error"] is String
          ? decoded["error"] as String
          : "リクエストに失敗しました(${response.statusCode})。";
      throw HistoryApiException(message);
    }
    return onOk(decoded);
  }

  Future<List<Person>> fetchPersons() => _send(
        () => _client.get(_uri("persons"), headers: _headers()),
        (body) => ((body as Map<String, dynamic>)["persons"] as List)
            .map((e) => Person.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<Person> createPerson(String nickname) => _send(
        () => _client.post(_uri("persons"), headers: _headers(), body: jsonEncode({"nickname": nickname})),
        (body) => Person.fromJson(body as Map<String, dynamic>),
      );

  Future<void> deletePerson(String personId) => _send(
        () => _client.delete(_uri("persons", {"person_id": personId}), headers: _headers()),
        (_) {},
      );

  Future<List<AnalysisSummary>> fetchAnalyses(String personId) => _send(
        () => _client.get(_uri("list", {"person_id": personId}), headers: _headers()),
        (body) => ((body as Map<String, dynamic>)["analyses"] as List)
            .map((e) => AnalysisSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<ChatResult> fetchChatDetail(String analysisId) => _send(
        () => _client.get(_uri("detail", {"analysis_id": analysisId}), headers: _headers()),
        (body) => ChatResult.fromJson(body as Map<String, dynamic>),
      );

  void dispose() => _client.close();
}
