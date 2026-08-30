/// api/functions/analyses.mjs のレスポンスに対応するモデル群(docs/design.md 4.2節)。
library;

class AnalysisSummary {
  final String id;
  final String headline;
  final int? interestScore;
  final String? phase;
  final DateTime createdAt;

  const AnalysisSummary({
    required this.id,
    required this.headline,
    required this.interestScore,
    required this.phase,
    required this.createdAt,
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) => AnalysisSummary(
        id: json["id"] as String,
        headline: json["headline"] as String,
        interestScore: json["interest_score"] as int?,
        phase: json["phase"] as String?,
        createdAt: DateTime.parse(json["created_at"] as String),
      );
}

class Person {
  final String id;
  final String nickname;
  final DateTime createdAt;
  final AnalysisSummary? latest;

  const Person({
    required this.id,
    required this.nickname,
    required this.createdAt,
    required this.latest,
  });

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json["id"] as String,
        nickname: json["nickname"] as String,
        createdAt: DateTime.parse(json["created_at"] as String),
        latest: json["latest"] == null
            ? null
            : AnalysisSummary.fromJson(json["latest"] as Map<String, dynamic>),
      );
}
