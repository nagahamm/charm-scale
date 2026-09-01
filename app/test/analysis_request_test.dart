import "package:flutter_test/flutter_test.dart";

import "package:charm_scale/models/analysis.dart";
import "package:charm_scale/models/person.dart";
import "package:charm_scale/screens/person_history_screen.dart";
import "package:charm_scale/services/analysis_api.dart";

AnalysisSummary summary(String id, String createdAt) => AnalysisSummary(
      id: id,
      headline: "見出し",
      interestScore: 60,
      phase: "興味あり",
      createdAt: DateTime.parse(createdAt),
    );

void main() {
  group("buildAnalysisRequestBody", () {
    test("会話モードでは person_id と previous_summary を送る", () {
      final body = buildAnalysisRequestBody(
        mode: AnalysisMode.chat,
        images: const [],
        personId: "p1",
        previousSummary: "前回は日程調整の直前で止まっていた。",
      );

      expect(body["mode"], "chat");
      expect(body["person_id"], "p1");
      expect(body["previous_summary"], "前回は日程調整の直前で止まっていた。");
    });

    test("続きの分析でなければ previous_summary を送らない", () {
      final body = buildAnalysisRequestBody(
        mode: AnalysisMode.chat,
        images: const [],
        personId: "p1",
      );

      expect(body.containsKey("previous_summary"), isFalse);
    });

    test("写真モードでは相手に紐づく項目を送らない", () {
      final body = buildAnalysisRequestBody(
        mode: AnalysisMode.photo,
        images: const [],
        personId: "p1",
        previousSummary: "前回の要約",
      );

      expect(body["mode"], "photo");
      expect(body.containsKey("person_id"), isFalse);
      expect(body.containsKey("previous_summary"), isFalse);
    });
  });

  group("latestOf", () {
    test("レスポンスの並び順によらず最新の分析を返す", () {
      final analyses = [
        summary("a", "2026-08-10T00:00:00Z"),
        summary("c", "2026-08-30T00:00:00Z"),
        summary("b", "2026-08-20T00:00:00Z"),
      ];

      expect(latestOf(analyses).id, "c");
      expect(latestOf(analyses.reversed.toList()).id, "c");
    });
  });
}
