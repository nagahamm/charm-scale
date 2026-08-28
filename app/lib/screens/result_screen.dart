import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../theme.dart";
import "../widgets/copy_button.dart";
import "../widgets/metric_bar.dart";
import "../widgets/rewrite_card.dart";
import "../widgets/score_gauge.dart";
import "../widgets/trend_chart.dart";

class ResultScreen extends StatelessWidget {
  final AnalysisMode mode;
  final Object result;

  const ResultScreen({super.key, required this.mode, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("分析結果")),
      body: SafeArea(
        child: switch (mode) {
          AnalysisMode.chat => _ChatResultView(result: result as ChatResult),
          AnalysisMode.photo => _PhotoResultView(result: result as PhotoResult),
          AnalysisMode.profile => _ProfileResultView(result: result as ProfileResult),
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
        if (result.rewrites.isNotEmpty) ...[
          const _SectionTitle("もっとこうすべきだった"),
          for (final r in result.rewrites)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RewriteCard(rewrite: r),
            ),
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

class _PhotoResultView extends StatelessWidget {
  final PhotoResult result;
  const _PhotoResultView({required this.result});

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
        if (result.goodPoints.isNotEmpty) ...[
          const _SectionTitle("良かった点"),
          for (final p in result.goodPoints) _BulletLine(p),
        ],
        if (result.badPoints.isNotEmpty) ...[
          const _SectionTitle("課題"),
          for (final p in result.badPoints) _BulletLine(p),
        ],
        if (result.retakes.isNotEmpty) ...[
          const _SectionTitle("撮り直し指示"),
          for (final r in result.retakes) _RetakeCard(retake: r),
        ],
      ],
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

class _ProfileResultView extends StatelessWidget {
  final ProfileResult result;
  const _ProfileResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(result.headline, style: textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(result.summary, style: textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            Chip(label: Text("年齢: ${result.reportedAge ?? '不明'}")),
            Chip(label: Text("職業: ${result.reportedOccupation ?? '不明'}")),
          ],
        ),
        const _SectionTitle("自己紹介の要約"),
        Text(result.bioSummary, style: textTheme.bodyMedium),
        if (result.talkingPoints.isNotEmpty) ...[
          const _SectionTitle("話題のきっかけ"),
          for (final t in result.talkingPoints) _BulletLine(t),
        ],
        if (result.notes.isNotEmpty) ...[
          const _SectionTitle("補足"),
          Text(result.notes, style: textTheme.bodySmall),
        ],
      ],
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
