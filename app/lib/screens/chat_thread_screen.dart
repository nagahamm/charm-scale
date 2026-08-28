import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../theme.dart";
import "../widgets/copy_button.dart";

/// 会話の再現(吹き出し)と、次に送る返信案。ResultScreen(分析結果)から「会話を見る」で遷移する。
class ChatThreadScreen extends StatelessWidget {
  final ChatResult result;
  const ChatThreadScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
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
                    child: Container(
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
                            child: Text(
                              candidate,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          CopyButton(text: candidate),
                        ],
                      ),
                    ),
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
