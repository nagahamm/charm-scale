import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:charm_scale/models/person.dart";
import "package:charm_scale/screens/person_history_screen.dart";
import "package:charm_scale/widgets/trend_chart.dart";

AnalysisSummary summary(String id, int? score, String createdAt) => AnalysisSummary(
      id: id,
      headline: "見出し",
      interestScore: score,
      phase: "興味あり",
      createdAt: DateTime.parse(createdAt),
    );

void main() {
  group("scoredInOrder", () {
    test("食いつき度数を持つ分析を古い順に並べる", () {
      final result = scoredInOrder([
        summary("c", 80, "2026-08-30T00:00:00Z"),
        summary("a", 40, "2026-08-10T00:00:00Z"),
        summary("b", 60, "2026-08-20T00:00:00Z"),
      ]);

      expect(result.map((a) => a.id).toList(), ["a", "b", "c"]);
      expect(result.map((a) => a.interestScore).toList(), [40, 60, 80]);
    });

    test("食いつき度数を持たない分析は除外する", () {
      final result = scoredInOrder([
        summary("a", null, "2026-08-10T00:00:00Z"),
        summary("b", 60, "2026-08-20T00:00:00Z"),
      ]);

      expect(result.map((a) => a.id).toList(), ["b"]);
    });

    test("空の履歴は空のまま", () {
      expect(scoredInOrder([]), isEmpty);
    });
  });

  group("TrendChart", () {
    testWidgets("2点以上あれば描画する", (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrendChart(values: [40, 60]))));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets("1点では推移にならないため描画しない", (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrendChart(values: [40]))));
      expect(tester.widget<TrendChart>(find.byType(TrendChart)).values, [40]);
      expect(find.byType(SizedBox), findsWidgets);
      final rendered = tester.renderObject(find.byType(TrendChart)).paintBounds;
      expect(rendered.height, 0);
    });
  });
}
