import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../theme.dart";
import "candidate_card.dart";

/// 会話の再現(吹き出し)。分析結果画面(ChatThreadScreen)と相手ごとの通し会話
/// (PersonThreadScreen)の両方から使う共通部品(docs/design.md 4.2節「相手ごとの通し会話」)。
class MessageBubble extends StatelessWidget {
  final TimelineEntry entry;
  const MessageBubble({super.key, required this.entry});

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
                    child: CandidateCard(text: candidate),
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
