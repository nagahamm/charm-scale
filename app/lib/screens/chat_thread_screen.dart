import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../services/analysis_api.dart";
import "../services/image_prep.dart";
import "../theme.dart";
import "../widgets/copy_button.dart";

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
              for (final entry in result.timeline) _MessageBubble(entry: entry),
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
            child: _CandidateCard(text: candidate),
          ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final String text;
  const _CandidateCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(text, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          CopyButton(text: text),
        ],
      ),
    );
  }
}

class _NextMoveCard extends StatelessWidget {
  final NextMove move;
  const _NextMoveCard({required this.move});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(label: Text(move.label), visualDensity: VisualDensity.compact),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(move.message, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                CopyButton(text: move.message),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(move.aim, style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TimelineEntry entry;
  const _MessageBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isSelf = entry.speaker == Speaker.self_;
    final hasRewrite = entry.rewrite != null;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSelf ? AppColors.primary : AppColors.surface,
        border: isSelf ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.excerpt,
            style: TextStyle(
              color: isSelf ? Colors.white : AppColors.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (hasRewrite) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note, size: 14, color: isSelf ? Colors.white : AppColors.primary),
                const SizedBox(width: 3),
                Text(
                  "もっとこうすべきだった",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelf ? Colors.white : AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: hasRewrite
                ? InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showRewriteSheet(context, entry),
                    child: bubble,
                  )
                : bubble,
          ),
        ],
      ),
    );
  }

  void _showRewriteSheet(BuildContext context, TimelineEntry entry) {
    final rewrite = entry.rewrite!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radius)),
      ),
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text("送った文", style: textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(entry.excerpt, style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.md),
                Text("問題点", style: textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(rewrite.issue, style: textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.md),
                Text("返信案", style: textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                for (final candidate in rewrite.improved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _CandidateCard(text: candidate),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text("理由", style: textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(rewrite.reason, style: textTheme.bodyMedium),
              ],
            ),
          ),
        );
      },
    );
  }
}
