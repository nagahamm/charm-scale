import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../theme.dart";
import "candidate_card.dart";

/// 会話の再現(吹き出し)。分析結果画面(ChatThreadScreen)と相手ごとの通し会話
/// (PersonThreadScreen)の両方から使う共通部品(docs/design.md 4.2節「相手ごとの通し会話」)。
///
/// entry.id が無い(まだ履歴に保存される前の、分析直後の結果)場合はメモを付けられない。
/// onSaveNote が渡されなければメモの導線自体を出さない。
class MessageBubble extends StatefulWidget {
  final TimelineEntry entry;
  final Future<void> Function(String entryId, String note)? onSaveNote;

  const MessageBubble({super.key, required this.entry, this.onSaveNote});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  late String? _userNote = widget.entry.userNote;

  bool get _canEditNote => widget.entry.id != null && widget.onSaveNote != null;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
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
      child: Column(
        crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
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
          if (_canEditNote) _buildNoteRow(),
        ],
      ),
    );
  }

  Widget _buildNoteRow() {
    final hasNote = _userNote != null && _userNote!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: InkWell(
        onTap: _editNote,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasNote ? Icons.sticky_note_2_outlined : Icons.note_add_outlined,
              size: 13,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                hasNote ? _userNote! : "メモを書く",
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _userNote ?? "");
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radius)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.md,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("このメッセージへのメモ", style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "例: このメッセージは失敗だった",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
                child: const Text("保存"),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSaveNote!(widget.entry.id!, result);
      if (mounted) setState(() => _userNote = result.isEmpty ? null : result);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text("メモの保存に失敗しました。")));
    }
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
