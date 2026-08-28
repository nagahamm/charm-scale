import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../theme.dart";

class MetricBar extends StatelessWidget {
  final String label;
  final Metric metric;

  const MetricBar({super.key, required this.label, required this.metric});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forScore(metric.score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text("${metric.score}", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            child: LinearProgressIndicator(
              value: metric.score / 100,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(metric.comment, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class MetricBarGroup extends StatelessWidget {
  final List<(String, Metric)> items;

  const MetricBarGroup({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, metric) in items) MetricBar(label: label, metric: metric),
      ],
    );
  }
}
