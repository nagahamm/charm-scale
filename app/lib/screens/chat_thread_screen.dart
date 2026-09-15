import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../models/analysis.dart";
import "../services/analysis_api.dart";
import "../services/image_prep.dart";
import "../theme.dart";
import "../widgets/candidate_card.dart";
import "../widgets/message_bubble.dart";

/// 会話の再現(吹き出し)・次に送る返信案・自分で書いてチェック。
/// ResultScreen(分析結果)から「会話を見る」で遷移する。
class ChatThreadScreen extends StatefulWidget {
  final ChatResult result;
  final List<PickedImage> images;
  const ChatThreadScreen({super.key, required this.result, required this.images});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _draftController = TextEditingController();
  DraftCheckResult? _checkResult;
  bool _checking = false;

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _runCheck() async {
    final draft = _draftController.text.trim();
    if (draft.isEmpty) return;
    setState(() {
      _checking = true;
      _checkResult = null;
    });

    final service = AnalysisApiService();
    final acc = AnalysisAccumulator();
    try {
      await for (final event in service.streamDraftCheck(images: widget.images, draftMessage: draft)) {
        acc.add(event);
        if (event is ErrorEvent) throw AnalysisApiException(event.message);
      }
      final json = acc.buildJson();
      final result = DraftCheckResult.fromJson(json);
      if (mounted) setState(() => _checkResult = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AnalysisApiException ? e.message : "チェックに失敗しました。")),
      );
    } finally {
      service.dispose();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("会話")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (result.timeline.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  "添削マーク付きの吹き出しをタップすると、もっとこうすべきだった返信案が見られます",
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              for (final entry in result.timeline) MessageBubble(entry: entry),
            ],
            if (result.nextMoves.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
                child: Text("次に送る返信案", style: textTheme.titleMedium),
              ),
              for (final m in result.nextMoves) _NextMoveCard(move: m),
            ],
            if (widget.images.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 2),
                child: Text("自分で書いてチェック", style: textTheme.titleMedium),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  "送ろうとしている文を確認できます",
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _draftController,
                        enabled: !_checking,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: "チェックする文",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: _checking ? null : _runCheck,
                        child: _checking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text("この文をチェックする"),
                      ),
                      if (_checkResult != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _DraftCheckResultView(result: _checkResult!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftCheckResultView extends StatelessWidget {
  final DraftCheckResult result;
  const _DraftCheckResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          label: Text(result.reaction.estimate),
          backgroundColor: const Color(0xFFEAF6EE),
          labelStyle: const TextStyle(color: Color(0xFF237A47), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(result.reaction.reasoning, style: textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        Text("想定される相手の返信(予測)", style: textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border, width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "AIによる予測",
                  style: textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(result.predictedReply, style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text("別の言い方の候補", style: textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        for (final candidate in result.candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: CandidateCard(text: candidate),
          ),
      ],
    );
  }
}

/// カードタップでクリップボードにコピーし、そのままコピー済み表示に切り替わる
/// (docs/requirements.md 3.1節)。
class _NextMoveCard extends StatefulWidget {
  final NextMove move;
  const _NextMoveCard({required this.move});

  @override
  State<_NextMoveCard> createState() => _NextMoveCardState();
}

class _NextMoveCardState extends State<_NextMoveCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.move.message));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: _copy,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(label: Text(widget.move.label), visualDensity: VisualDensity.compact),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.move.message,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  CopiedIndicator(copied: _copied),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(widget.move.aim, style: textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

