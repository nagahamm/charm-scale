import "package:flutter/material.dart";

import "../theme.dart";

/// 文末に添える出典タグ。Google の AI Overview のような、簡略化したドメイン名だけを見せる小さなチップ。
class CitationChip extends StatelessWidget {
  final String label;

  const CitationChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
      ),
    );
  }
}
