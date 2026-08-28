/// api/functions/analyse.mjs のレスポンススキーマに対応するモデル群。
/// スキーマの定義はサーバー側(analyse.mjs)に集約されているため、ここは対応する形をなぞるのみ。
library;

enum AnalysisMode { chat, photo }

extension AnalysisModeApi on AnalysisMode {
  String get apiValue => switch (this) {
        AnalysisMode.chat => "chat",
        AnalysisMode.photo => "photo",
      };
}

class Metric {
  final int score;
  final String comment;

  const Metric({required this.score, required this.comment});

  factory Metric.fromJson(Map<String, dynamic> json) => Metric(
        score: json["score"] as int,
        comment: json["comment"] as String,
      );
}

class ChatMetrics {
  final Metric replySpeed;
  final Metric volumeBalance;
  final Metric questionReturn;
  final Metric emotionalExpression;
  final Metric initiative;

  const ChatMetrics({
    required this.replySpeed,
    required this.volumeBalance,
    required this.questionReturn,
    required this.emotionalExpression,
    required this.initiative,
  });

  factory ChatMetrics.fromJson(Map<String, dynamic> json) => ChatMetrics(
        replySpeed: Metric.fromJson(json["reply_speed"] as Map<String, dynamic>),
        volumeBalance: Metric.fromJson(json["volume_balance"] as Map<String, dynamic>),
        questionReturn: Metric.fromJson(json["question_return"] as Map<String, dynamic>),
        emotionalExpression: Metric.fromJson(json["emotional_expression"] as Map<String, dynamic>),
        initiative: Metric.fromJson(json["initiative"] as Map<String, dynamic>),
      );

  List<(String, Metric)> get labeled => [
        ("返信速度", replySpeed),
        ("文量バランス", volumeBalance),
        ("質問返し", questionReturn),
        ("感情表現", emotionalExpression),
        ("主導権", initiative),
      ];
}

class PhotoMetrics {
  final Metric firstImpression;
  final Metric expression;
  final Metric compositionQuality;
  final Metric stylingCleanliness;
  final Metric backgroundSituation;
  final Metric overallImpressionConsistency;

  const PhotoMetrics({
    required this.firstImpression,
    required this.expression,
    required this.compositionQuality,
    required this.stylingCleanliness,
    required this.backgroundSituation,
    required this.overallImpressionConsistency,
  });

  factory PhotoMetrics.fromJson(Map<String, dynamic> json) => PhotoMetrics(
        firstImpression: Metric.fromJson(json["first_impression"] as Map<String, dynamic>),
        expression: Metric.fromJson(json["expression"] as Map<String, dynamic>),
        compositionQuality: Metric.fromJson(json["composition_quality"] as Map<String, dynamic>),
        stylingCleanliness: Metric.fromJson(json["styling_cleanliness"] as Map<String, dynamic>),
        backgroundSituation: Metric.fromJson(json["background_situation"] as Map<String, dynamic>),
        overallImpressionConsistency:
            Metric.fromJson(json["overall_impression_consistency"] as Map<String, dynamic>),
      );

  List<(String, Metric)> get labeled => [
        ("第一印象", firstImpression),
        ("表情", expression),
        ("構図・画質", compositionQuality),
        ("服装・清潔感", stylingCleanliness),
        ("背景・シチュエーション", backgroundSituation),
        ("全体印象の一貫性", overallImpressionConsistency),
      ];
}

enum Speaker { self_, partner }

class TimelineEntry {
  final Speaker speaker;
  final String excerpt;
  final int interest;
  final String note;

  const TimelineEntry({
    required this.speaker,
    required this.excerpt,
    required this.interest,
    required this.note,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        speaker: json["speaker"] == "self" ? Speaker.self_ : Speaker.partner,
        excerpt: json["excerpt"] as String,
        interest: json["interest"] as int,
        note: json["note"] as String,
      );
}

class Rewrite {
  final String original;
  final String issue;
  final String improved;
  final String reason;

  const Rewrite({
    required this.original,
    required this.issue,
    required this.improved,
    required this.reason,
  });

  factory Rewrite.fromJson(Map<String, dynamic> json) => Rewrite(
        original: json["original"] as String,
        issue: json["issue"] as String,
        improved: json["improved"] as String,
        reason: json["reason"] as String,
      );
}

class NextMove {
  final String label;
  final String message;
  final String aim;

  const NextMove({required this.label, required this.message, required this.aim});

  factory NextMove.fromJson(Map<String, dynamic> json) => NextMove(
        label: json["label"] as String,
        message: json["message"] as String,
        aim: json["aim"] as String,
      );
}

class ProfileInfo {
  final String? reportedAge;
  final String? reportedOccupation;
  final String? likesCount;
  final String bioSummary;
  final List<ProfileAttribute> attributes;
  final List<String> tags;
  final List<String> talkingPoints;
  final String notes;

  const ProfileInfo({
    required this.reportedAge,
    required this.reportedOccupation,
    required this.likesCount,
    required this.bioSummary,
    required this.attributes,
    required this.tags,
    required this.talkingPoints,
    required this.notes,
  });

  factory ProfileInfo.fromJson(Map<String, dynamic> json) => ProfileInfo(
        reportedAge: json["reported_age"] as String?,
        reportedOccupation: json["reported_occupation"] as String?,
        likesCount: json["likes_count"] as String?,
        bioSummary: json["bio_summary"] as String,
        attributes: (json["attributes"] as List)
            .map((e) => ProfileAttribute.fromJson(e as Map<String, dynamic>))
            .toList(),
        tags: (json["tags"] as List).cast<String>(),
        talkingPoints: (json["talking_points"] as List).cast<String>(),
        notes: json["notes"] as String,
      );
}

class ProfileAttribute {
  final String label;
  final String value;

  const ProfileAttribute({required this.label, required this.value});

  factory ProfileAttribute.fromJson(Map<String, dynamic> json) => ProfileAttribute(
        label: json["label"] as String,
        value: json["value"] as String,
      );
}

class ChatResult {
  final String headline;
  final int interestScore;
  final String phase;
  final String summary;
  final ProfileInfo? profile;
  final ChatMetrics metrics;
  final List<TimelineEntry> timeline;
  final List<String> goodPoints;
  final List<String> badPoints;
  final List<Rewrite> rewrites;
  final List<NextMove> nextMoves;

  const ChatResult({
    required this.headline,
    required this.interestScore,
    required this.phase,
    required this.summary,
    required this.profile,
    required this.metrics,
    required this.timeline,
    required this.goodPoints,
    required this.badPoints,
    required this.rewrites,
    required this.nextMoves,
  });

  factory ChatResult.fromJson(Map<String, dynamic> json) => ChatResult(
        headline: json["headline"] as String,
        interestScore: json["interest_score"] as int,
        phase: json["phase"] as String,
        summary: json["summary"] as String,
        profile: json["profile"] == null
            ? null
            : ProfileInfo.fromJson(json["profile"] as Map<String, dynamic>),
        metrics: ChatMetrics.fromJson(json["metrics"] as Map<String, dynamic>),
        timeline: (json["timeline"] as List)
            .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        goodPoints: (json["good_points"] as List).cast<String>(),
        badPoints: (json["bad_points"] as List).cast<String>(),
        rewrites:
            (json["rewrites"] as List).map((e) => Rewrite.fromJson(e as Map<String, dynamic>)).toList(),
        nextMoves:
            (json["next_moves"] as List).map((e) => NextMove.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class Retake {
  final String title;
  final String how;
  final String reason;

  const Retake({required this.title, required this.how, required this.reason});

  factory Retake.fromJson(Map<String, dynamic> json) => Retake(
        title: json["title"] as String,
        how: json["how"] as String,
        reason: json["reason"] as String,
      );
}

class Positioning {
  final String estimate;
  final String basis;
  final String sourceUrl;
  final String disclaimer;

  const Positioning({
    required this.estimate,
    required this.basis,
    required this.sourceUrl,
    required this.disclaimer,
  });

  factory Positioning.fromJson(Map<String, dynamic> json) => Positioning(
        estimate: json["estimate"] as String,
        basis: json["basis"] as String,
        sourceUrl: json["source_url"] as String,
        disclaimer: json["disclaimer"] as String,
      );

  /// 出典表示用の簡略ラベル(例: "laskoi.jp")。
  String get sourceLabel {
    final host = Uri.tryParse(sourceUrl)?.host ?? sourceUrl;
    return host.startsWith("www.") ? host.substring(4) : host;
  }
}

class PhotoResult {
  final String headline;
  final int interestScore;
  final String summary;
  final PhotoMetrics metrics;
  final List<String> goodPoints;
  final List<String> badPoints;
  final List<Retake> retakes;
  final List<Rewrite> bioRewrites;
  final Positioning? positioning;

  const PhotoResult({
    required this.headline,
    required this.interestScore,
    required this.summary,
    required this.metrics,
    required this.goodPoints,
    required this.badPoints,
    required this.retakes,
    required this.bioRewrites,
    required this.positioning,
  });

  factory PhotoResult.fromJson(Map<String, dynamic> json) => PhotoResult(
        headline: json["headline"] as String,
        interestScore: json["interest_score"] as int,
        summary: json["summary"] as String,
        metrics: PhotoMetrics.fromJson(json["metrics"] as Map<String, dynamic>),
        goodPoints: (json["good_points"] as List).cast<String>(),
        badPoints: (json["bad_points"] as List).cast<String>(),
        retakes:
            (json["retakes"] as List).map((e) => Retake.fromJson(e as Map<String, dynamic>)).toList(),
        bioRewrites: (json["bio_rewrites"] as List)
            .map((e) => Rewrite.fromJson(e as Map<String, dynamic>))
            .toList(),
        positioning: json["positioning"] == null
            ? null
            : Positioning.fromJson(json["positioning"] as Map<String, dynamic>),
      );
}
