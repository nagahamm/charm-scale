import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../theme.dart";
import "copy_button.dart";

class RewriteCard extends StatelessWidget {
  final Rewrite rewrite;

  const RewriteCard({super.key, required this.rewrite});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("送った文", style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(rewrite.original, style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Text("問題点", style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(rewrite.issue, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            Text("改善文", style: textTheme.bodySmall),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    rewrite.improved,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                CopyButton(text: rewrite.improved),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("理由", style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(rewrite.reason, style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
