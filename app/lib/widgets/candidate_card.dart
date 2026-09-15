import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../theme.dart";

/// タップでクリップボードにコピーし、カード自体がコピー済み表示に切り替わる
/// (docs/requirements.md 3.1節: SnackBarのような一時的な通知ではなく、恒常的な状態表示にする)。
class CandidateCard extends StatefulWidget {
  final String text;
  const CandidateCard({super.key, required this.text});

  @override
  State<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<CandidateCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: _copied ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(widget.text, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: AppSpacing.sm),
            CopiedIndicator(copied: _copied),
          ],
        ),
      ),
    );
  }
}

class CopiedIndicator extends StatelessWidget {
  final bool copied;
  const CopiedIndicator({super.key, required this.copied});

  @override
  Widget build(BuildContext context) {
    if (!copied) return const Icon(Icons.copy_outlined, size: 20, color: AppColors.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          "コピー済み",
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
