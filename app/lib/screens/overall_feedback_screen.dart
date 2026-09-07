import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../models/person.dart";
import "../services/history_api.dart";
import "../theme.dart";
import "../widgets/metric_bar.dart";
import "../widgets/trend_chart.dart";

/// Person をまたいだ全体的なフィードバック(docs/requirements.md 3.5節)。
class OverallFeedbackScreen extends StatefulWidget {
  const OverallFeedbackScreen({super.key});

  @override
  State<OverallFeedbackScreen> createState() => _OverallFeedbackScreenState();
}

class _OverallFeedbackScreenState extends State<OverallFeedbackScreen> {
  final _api = HistoryApiService();
  late Future<FeedbackOverview> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchOverview();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = _api.fetchOverview();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("全体フィードバック")),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<FeedbackOverview>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        snapshot.error is HistoryApiException
                            ? (snapshot.error as HistoryApiException).message
                            : "読み込みに失敗しました。",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }
              final overview = snapshot.data!;
              if (overview.chat.count == 0 && overview.photo.count == 0) {
                return ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text("まだ分析がありません。", textAlign: TextAlign.center),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _ModeFeedbackCard(title: "会話モード", feedback: overview.chat),
                  const SizedBox(height: AppSpacing.md),
                  _ModeFeedbackCard(title: "写真モード", feedback: overview.photo),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ModeFeedbackCard extends StatelessWidget {
  final String title;
  final ModeFeedback feedback;

  const _ModeFeedbackCard({required this.title, required this.feedback});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (feedback.count == 0)
              Text("まだ分析がありません", style: textTheme.bodySmall)
            else ...[
              if (feedback.trend.length >= 2) ...[
                Text("推移", style: textTheme.bodySmall),
                TrendChart(values: feedback.trend),
                const SizedBox(height: AppSpacing.sm),
              ],
              for (final metric in feedback.metrics)
                MetricBar(
                  label: metric.label,
                  metric: Metric(score: metric.score, comment: "${metric.count}件の平均"),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
