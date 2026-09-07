import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

import "package:charm_scale/models/analysis.dart";
import "package:charm_scale/screens/chat_thread_screen.dart";

ChatResult _chatResultWithNextMove(String message) => ChatResult(
      headline: "見出し",
      interestScore: 70,
      phase: "興味あり",
      summary: "要約",
      profile: null,
      metrics: ChatMetrics.fromJson({
        "reply_speed": {"score": 70, "comment": ""},
        "volume_balance": {"score": 70, "comment": ""},
        "question_return": {"score": 70, "comment": ""},
        "emotional_expression": {"score": 70, "comment": ""},
        "initiative": {"score": 70, "comment": ""},
      }),
      timeline: const [],
      goodPoints: const [],
      badPoints: const [],
      nextMoves: [NextMove(label: "カジュアル", message: message, aim: "距離を縮める")],
    );

void main() {
  // テスト環境には Clipboard のプラットフォームチャンネルの応答が無く、
  // 応答を待つ Future が永久に解決しないため、モックハンドラを登録する。
  String? clipboardText;
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == "Clipboard.setData") {
        clipboardText = (call.arguments as Map)["text"] as String?;
        return null;
      }
      if (call.method == "Clipboard.getData") {
        return {"text": clipboardText};
      }
      return null;
    },
  );

  // docs/requirements.md 3.1節: カードタップでコピーされ、カード自体がコピー済み表示に切り替わる
  // (SnackBarのような一時的な通知ではなく、恒常的な状態表示にする、#19)。
  testWidgets("次に送る返信案カードをタップするとコピーされ、コピー済み表示に切り替わる", (tester) async {
    const message = "今度の週末、一緒にご飯どうですか?";
    await tester.pumpWidget(
      MaterialApp(
        home: ChatThreadScreen(result: _chatResultWithNextMove(message), images: const []),
      ),
    );

    expect(find.text("コピー済み"), findsNothing);

    final cardInkWell = find.ancestor(of: find.text(message), matching: find.byType(InkWell));
    await tester.tap(cardInkWell);
    await tester.pumpAndSettle();

    expect(find.text("コピー済み"), findsOneWidget);

    expect(clipboardText, message);
  });
}
