import "package:flutter_test/flutter_test.dart";

import "package:charm_scale/models/analysis.dart";

Map<String, dynamic> _metric(int score, [String comment = "c"]) => {"score": score, "comment": comment};

void main() {
  group("ChatResult.fromJson", () {
    test("parses a full chat response", () {
      final json = {
        "headline": "見出し",
        "interest_score": 72,
        "phase": "興味あり",
        "summary": "要約",
        "profile": {
          "reported_age": "28歳",
          "reported_occupation": null,
          "likes_count": "120",
          "bio_summary": "自己紹介の要約",
          "attributes": [
            {"label": "血液型", "value": "A型"},
            {"label": "身長", "value": "160cm"},
          ],
          "tags": ["旅行", "カフェ巡り"],
          "talking_points": ["話題1", "話題2"],
          "notes": "職業の記載なし",
        },
        "metrics": {
          "reply_speed": _metric(80),
          "volume_balance": _metric(60),
          "question_return": _metric(50),
          "emotional_expression": _metric(70),
          "initiative": _metric(40),
        },
        "timeline": [
          {"speaker": "self", "excerpt": "こんにちは", "interest": 50, "note": "note1"},
          {"speaker": "partner", "excerpt": "こんにちは!", "interest": 65, "note": "note2"},
        ],
        "good_points": ["良い点1"],
        "bad_points": ["課題1"],
        "rewrites": [
          {"original": "元の文", "issue": "問題点", "improved": "改善文", "reason": "理由"},
        ],
        "next_moves": [
          {"label": "軽め", "message": "メッセージ1", "aim": "狙い1"},
          {"label": "踏み込む", "message": "メッセージ2", "aim": "狙い2"},
        ],
      };

      final result = ChatResult.fromJson(json);

      expect(result.interestScore, 72);
      expect(result.phase, "興味あり");
      expect(result.metrics.replySpeed.score, 80);
      expect(result.metrics.labeled.map((e) => e.$1), [
        "返信速度",
        "文量バランス",
        "質問返し",
        "感情表現",
        "主導権",
      ]);
      expect(result.timeline, hasLength(2));
      expect(result.timeline.first.speaker, Speaker.self_);
      expect(result.timeline.last.speaker, Speaker.partner);
      expect(result.rewrites.single.improved, "改善文");
      expect(result.nextMoves, hasLength(2));
      expect(result.profile?.reportedAge, "28歳");
      expect(result.profile?.reportedOccupation, isNull);
      expect(result.profile?.likesCount, "120");
      expect(result.profile?.talkingPoints, hasLength(2));
      expect(result.profile?.attributes.map((a) => a.label), ["血液型", "身長"]);
      expect(result.profile?.tags, ["旅行", "カフェ巡り"]);
    });

    test("profile is null when no profile screenshots were sent", () {
      final json = {
        "headline": "見出し",
        "interest_score": 40,
        "phase": "様子見",
        "summary": "要約",
        "profile": null,
        "metrics": {
          "reply_speed": _metric(50),
          "volume_balance": _metric(50),
          "question_return": _metric(50),
          "emotional_expression": _metric(50),
          "initiative": _metric(50),
        },
        "timeline": [],
        "good_points": [],
        "bad_points": [],
        "rewrites": [],
        "next_moves": [
          {"label": "軽め", "message": "メッセージ1", "aim": "狙い1"},
          {"label": "踏み込む", "message": "メッセージ2", "aim": "狙い2"},
        ],
      };

      final result = ChatResult.fromJson(json);

      expect(result.profile, isNull);
    });
  });

  group("PhotoResult.fromJson", () {
    test("parses a full photo response", () {
      final json = {
        "headline": "見出し",
        "interest_score": 55,
        "summary": "要約",
        "metrics": {
          "first_impression": _metric(60),
          "expression": _metric(50),
          "composition_quality": _metric(70),
          "styling_cleanliness": _metric(65),
          "background_situation": _metric(40),
        },
        "good_points": ["良い点"],
        "bad_points": ["課題"],
        "retakes": [
          {"title": "屋外で", "how": "自然光の下で", "reason": "肌が明るく写る"},
        ],
      };

      final result = PhotoResult.fromJson(json);

      expect(result.interestScore, 55);
      expect(result.metrics.labeled.map((e) => e.$1), [
        "第一印象",
        "表情",
        "構図・画質",
        "服装・清潔感",
        "背景・シチュエーション",
      ]);
      expect(result.retakes.single.title, "屋外で");
    });
  });
}
