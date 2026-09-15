import "package:flutter/material.dart";

import "../models/person.dart";
import "../services/history_api.dart";
import "../theme.dart";
import "../widgets/message_bubble.dart";

/// 相手ごとの通し会話(docs/requirements.md 3.3節「相手ごとの通し会話」、#20)。
/// その相手に紐づく全Analysisのtimelineを、日時順に連結して表示する。
class PersonThreadScreen extends StatefulWidget {
  final Person person;
  const PersonThreadScreen({super.key, required this.person});

  @override
  State<PersonThreadScreen> createState() => _PersonThreadScreenState();
}

class _PersonThreadScreenState extends State<PersonThreadScreen> {
  final _api = HistoryApiService();
  late final Future<PersonThread> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchThread(widget.person.id);
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.person.nickname}との会話")),
      body: SafeArea(
        child: FutureBuilder<PersonThread>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    snapshot.error is HistoryApiException
                        ? (snapshot.error as HistoryApiException).message
                        : "読み込みに失敗しました。",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final timeline = snapshot.data?.timeline ?? const [];
            if (timeline.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text("まだ分析がありません。")));
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    "添削マーク付きの吹き出しをタップすると、もっとこうすべきだった返信案が見られます",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                for (final entry in timeline) MessageBubble(entry: entry),
              ],
            );
          },
        ),
      ),
    );
  }
}
