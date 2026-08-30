import "package:flutter_test/flutter_test.dart";

import "package:charm_scale/models/person.dart";

void main() {
  group("Person.fromJson", () {
    test("parses a person with a latest analysis", () {
      final json = {
        "id": "p1",
        "nickname": "Aさん",
        "created_at": "2026-08-01T00:00:00Z",
        "latest": {
          "id": "a1",
          "headline": "見出し",
          "interest_score": 70,
          "phase": "興味あり",
          "created_at": "2026-08-20T00:00:00Z",
        },
      };

      final person = Person.fromJson(json);

      expect(person.id, "p1");
      expect(person.nickname, "Aさん");
      expect(person.latest, isNotNull);
      expect(person.latest?.headline, "見出し");
      expect(person.latest?.interestScore, 70);
      expect(person.latest?.phase, "興味あり");
    });

    test("latest is null when the person has no analysis yet", () {
      final json = {
        "id": "p2",
        "nickname": "Bさん",
        "created_at": "2026-08-01T00:00:00Z",
        "latest": null,
      };

      final person = Person.fromJson(json);

      expect(person.latest, isNull);
    });
  });

  group("AnalysisSummary.fromJson", () {
    test("parses a summary", () {
      final json = {
        "id": "a1",
        "headline": "見出し",
        "interest_score": 55,
        "phase": "様子見",
        "created_at": "2026-08-15T00:00:00Z",
      };

      final summary = AnalysisSummary.fromJson(json);

      expect(summary.id, "a1");
      expect(summary.interestScore, 55);
      expect(summary.createdAt, DateTime.parse("2026-08-15T00:00:00Z"));
    });
  });
}
