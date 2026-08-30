import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;

import "../models/analysis.dart";
import "auth_service.dart";
import "image_prep.dart";

/// ビルド時に --dart-define=API_BASE_URL=https://your-site.netlify.app を渡す。
const _apiBase = String.fromEnvironment("API_BASE_URL");

sealed class AnalysisEvent {
  const AnalysisEvent();
}

class StatusEvent extends AnalysisEvent {
  final String text;
  const StatusEvent(this.text);
}

class DeltaEvent extends AnalysisEvent {
  final String text;
  const DeltaEvent(this.text);
}

class ErrorEvent extends AnalysisEvent {
  final String message;
  const ErrorEvent(this.message);
}

class DoneEvent extends AnalysisEvent {
  const DoneEvent();
}

class AnalysisApiException implements Exception {
  final String message;
  const AnalysisApiException(this.message);

  @override
  String toString() => message;
}

class AnalysisApiService {
  final http.Client _client;

  AnalysisApiService({http.Client? client}) : _client = client ?? http.Client();

  Stream<AnalysisEvent> stream({
    required AnalysisMode mode,
    required List<PickedImage> images,
    List<PickedImage> profileImages = const [],
    String context = "",
    String? personId,
  }) => _stream({
        "mode": mode.apiValue,
        "images": images.map((i) => i.toJson()).toList(),
        "profile_images": profileImages.map((i) => i.toJson()).toList(),
        "context": context,
        if (personId != null) "person_id": personId,
      });

  Stream<AnalysisEvent> streamDraftCheck({
    required List<PickedImage> images,
    required String draftMessage,
  }) => _stream({
        "mode": "draft_check",
        "images": images.map((i) => i.toJson()).toList(),
        "draft_message": draftMessage,
      });

  Stream<AnalysisEvent> _stream(Map<String, Object?> body) async* {
    if (_apiBase.isEmpty) {
      throw const AnalysisApiException(
        "API_BASE_URL が未設定です。--dart-define=API_BASE_URL=... を指定してビルドしてください。",
      );
    }

    final accessToken = AuthService().accessToken;
    final request = http.Request("POST", Uri.parse("$_apiBase/api/analyse"))
      ..headers["content-type"] = "application/json; charset=utf-8"
      ..body = jsonEncode(body);
    if (accessToken != null) request.headers["authorization"] = "Bearer $accessToken";

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AnalysisApiException(_extractErrorMessage(body) ?? "リクエストに失敗しました(${response.statusCode})。");
    }

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final event = jsonDecode(line) as Map<String, dynamic>;
      switch (event["type"]) {
        case "status":
          yield StatusEvent(event["text"] as String? ?? "");
        case "delta":
          yield DeltaEvent(event["text"] as String? ?? "");
        case "error":
          yield ErrorEvent(event["message"] as String? ?? "解析に失敗しました。");
        case "done":
          yield const DoneEvent();
      }
    }
  }

  String? _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded["error"] is String) {
        return decoded["error"] as String;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  void dispose() => _client.close();
}

/// delta イベントのテキストを連結して最終 JSON を組み立てる。
class AnalysisAccumulator {
  final StringBuffer _buffer = StringBuffer();
  String? lastStatus;

  void add(AnalysisEvent event) {
    switch (event) {
      case StatusEvent(:final text):
        lastStatus = text;
      case DeltaEvent(:final text):
        _buffer.write(text);
      case ErrorEvent():
      case DoneEvent():
        break;
    }
  }

  Map<String, dynamic> buildJson() => jsonDecode(_buffer.toString()) as Map<String, dynamic>;
}
