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

/// 項目別スコアの平均(docs/design.md 4.3節)。1件の Analysis の Metric とは違い
/// 個別のコメントを持たず、平均元の件数(count)を持つ。
class MetricAverage {
  final String label;
  final int score;
  final int count;

  const MetricAverage({required this.label, required this.score, required this.count});

  factory MetricAverage.fromJson(Map<String, dynamic> json) => MetricAverage(
        label: json["label"] as String,
        score: json["score"] as int,
        count: json["count"] as int,
      );
}

/// 全体的なフィードバックのうち、chat または photo いずれか片方のモード分。
class ModeFeedback {
  final int count;
  final List<int> trend;
  final List<MetricAverage> metrics;

  const ModeFeedback({required this.count, required this.trend, required this.metrics});

  factory ModeFeedback.fromJson(Map<String, dynamic> json) => ModeFeedback(
        count: json["count"] as int,
        trend: (json["trend"] as List).cast<int>(),
        metrics:
            (json["metrics"] as List).map((e) => MetricAverage.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Person をまたいだ全体的なフィードバック(docs/requirements.md 3.5節)。
class FeedbackOverview {
  final ModeFeedback chat;
  final ModeFeedback photo;

  const FeedbackOverview({required this.chat, required this.photo});

  factory FeedbackOverview.fromJson(Map<String, dynamic> json) => FeedbackOverview(
        chat: ModeFeedback.fromJson(json["chat"] as Map<String, dynamic>),
        photo: ModeFeedback.fromJson(json["photo"] as Map<String, dynamic>),
      );
}
