import "dart:convert";

import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../services/image_prep.dart";
import "../theme.dart";
import "../widgets/citation_chip.dart";
import "../widgets/copy_button.dart";
import "../widgets/metric_bar.dart";
import "../widgets/rewrite_card.dart";
import "../widgets/score_gauge.dart";
import "../widgets/trend_chart.dart";

class ResultScreen extends StatelessWidget {
  final AnalysisMode mode;
  final Object result;
  final List<PickedImage> images;

  const ResultScreen({super.key, required this.mode, required this.result, required this.images});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("分析結果")),
      body: SafeArea(
        child: switch (mode) {
          AnalysisMode.chat => _ChatResultView(result: result as ChatResult),
          AnalysisMode.photo => _PhotoResultView(result: result as PhotoResult, images: images),
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ChatResultView extends StatelessWidget {
  final ChatResult result;
  const _ChatResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(child: ScoreGauge(score: result.interestScore, label: "食いつき度数")),
        const SizedBox(height: AppSpacing.sm),
        Center(child: Chip(label: Text(result.phase))),
        const SizedBox(height: AppSpacing.md),
        Text(result.headline, style: textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(result.summary, style: textTheme.bodyMedium),
        if (result.profile != null) ...[
          const _SectionTitle("相手のプロフィール"),
          _ProfileSection(profile: result.profile!),
        ],
        const _SectionTitle("項目別スコア"),
        MetricBarGroup(items: result.metrics.labeled),
        if (result.timeline.length >= 2) ...[
          const _SectionTitle("食いつき度数の推移"),
          TrendChart(timeline: result.timeline),
        ],
        if (result.goodPoints.isNotEmpty) ...[
          const _SectionTitle("良かった点"),
          for (final p in result.goodPoints) _BulletLine(p),
        ],
        if (result.badPoints.isNotEmpty) ...[
          const _SectionTitle("課題"),
          for (final p in result.badPoints) _BulletLine(p),
        ],
        if (result.timeline.isNotEmpty) ...[
          const _SectionTitle("会話の再現"),
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              "添削マーク付きの吹き出しをタップすると、もっとこうすべきだった添削が見られます",
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          _ChatBubbleTimeline(timeline: result.timeline),
        ],
        if (result.nextMoves.isNotEmpty) ...[
          const _SectionTitle("次に送る返信案"),
          for (final m in result.nextMoves) _NextMoveCard(move: m),
        ],
      ],
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

class _ChatBubbleTimeline extends StatelessWidget {
  final List<TimelineEntry> timeline;
  const _ChatBubbleTimeline({required this.timeline});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in timeline) _MessageBubble(entry: entry),
      ],
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Text("改善文", style: textTheme.bodySmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        rewrite.improved,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    CopyButton(text: rewrite.improved),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
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

class _PhotoResultView extends StatelessWidget {
  final PhotoResult result;
  final List<PickedImage> images;
  const _PhotoResultView({required this.result, required this.images});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(child: ScoreGauge(score: result.interestScore, label: "総合スコア")),
        const SizedBox(height: AppSpacing.md),
        Text(result.headline, style: textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(result.summary, style: textTheme.bodyMedium),
        const _SectionTitle("項目別評価"),
        MetricBarGroup(items: result.metrics.labeled),
        if (result.photos.isNotEmpty) ...[
          const _SectionTitle("写真ごとの評価"),
          for (var i = 0; i < result.photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _PhotoEvalCard(
                isMain: i == 0,
                image: i < images.length ? images[i] : null,
                evaluation: result.photos[i],
              ),
            ),
        ],
        if (result.bioRewrites.isNotEmpty) ...[
          const _SectionTitle("プロフィール文の添削"),
          for (final r in result.bioRewrites)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RewriteCard(rewrite: r),
            ),
        ],
        if (result.positioning != null) ...[
          const _SectionTitle("いいね数の目安"),
          _PositioningCard(positioning: result.positioning!),
        ],
      ],
    );
  }
}

class _PhotoEvalCard extends StatelessWidget {
  final bool isMain;
  final PickedImage? image;
  final PhotoEvaluation evaluation;

  const _PhotoEvalCard({required this.isMain, required this.image, required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = AppColors.forScore(evaluation.score);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      child: image != null
                          ? Image.memory(
                              const Base64Decoder().convert(image!.base64Data),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 72,
                              height: 72,
                              color: AppColors.border,
                            ),
                    ),
                    if (isMain)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "メイン",
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(
                            label: Text(evaluation.category.label),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          const Spacer(),
                          Text(
                            "${evaluation.score}",
                            style: textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(evaluation.comment, style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (evaluation.retake != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _RetakeCard(retake: evaluation.retake!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetakeCard extends StatelessWidget {
  final Retake retake;
  const _RetakeCard({required this.retake});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(retake.title, style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(retake.how, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(retake.reason, style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PositioningCard extends StatelessWidget {
  final Positioning positioning;
  const _PositioningCard({required this.positioning});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(positioning.estimate, style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text.rich(
              TextSpan(
                style: textTheme.bodyMedium,
                children: [
                  TextSpan(text: "${positioning.basis} "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: CitationChip(label: positioning.sourceLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(positioning.disclaimer, style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final ProfileInfo profile;
  const _ProfileSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                Chip(label: Text("年齢: ${profile.reportedAge ?? '不明'}")),
                Chip(label: Text("職業: ${profile.reportedOccupation ?? '不明'}")),
                if (profile.likesCount != null) Chip(label: Text("いいね: ${profile.likesCount}")),
              ],
            ),
            if (profile.attributes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Column(
                children: [
                  for (final a in profile.attributes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(a.label, style: textTheme.bodySmall),
                          ),
                          Expanded(child: Text(a.value, style: textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (profile.tags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final t in profile.tags)
                    Chip(label: Text(t), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text("自己紹介", style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(profile.bioSummary, style: textTheme.bodyMedium),
            if (profile.talkingPoints.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text("話題のきっかけ", style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              for (final t in profile.talkingPoints) _BulletLine(t),
            ],
            if (profile.notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(profile.notes, style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  final String text;
  const _BulletLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("・"),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
