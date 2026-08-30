import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../models/person.dart";
import "../services/history_api.dart";
import "../theme.dart";
import "result_screen.dart";

/// 特定の Person(相手)の分析履歴一覧(docs/requirements.md 4.2節)。
class PersonHistoryScreen extends StatefulWidget {
  final Person person;
  const PersonHistoryScreen({super.key, required this.person});

  @override
  State<PersonHistoryScreen> createState() => _PersonHistoryScreenState();
}

class _PersonHistoryScreenState extends State<PersonHistoryScreen> {
  final _api = HistoryApiService();
  late Future<List<AnalysisSummary>> _future;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchAnalyses(widget.person.id);
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _open(AnalysisSummary summary) async {
    setState(() => _openingId = summary.id);
    try {
      final result = await _api.fetchChatDetail(summary.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(mode: AnalysisMode.chat, result: result, images: const []),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is HistoryApiException ? e.message : "読み込みに失敗しました。")),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.person.nickname)),
      body: SafeArea(
        child: FutureBuilder<List<AnalysisSummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    snapshot.error is HistoryApiException
                        ? (snapshot.error as HistoryApiException).message
                        : "読み込みに失敗しました。",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final analyses = snapshot.data ?? const [];
            if (analyses.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text("まだ分析がありません。")));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: analyses.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final summary = analyses[index];
                final loading = _openingId == summary.id;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    onTap: loading ? null : () => _open(summary),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (summary.interestScore != null)
                                      Text(
                                        "${summary.interestScore}",
                                        style: textTheme.titleMedium?.copyWith(
                                          color: AppColors.forScore(summary.interestScore!),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (summary.phase != null) ...[
                                      const SizedBox(width: AppSpacing.sm),
                                      Chip(label: Text(summary.phase!), visualDensity: VisualDensity.compact),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(summary.headline, style: textTheme.bodyMedium),
                                const SizedBox(height: 2),
                                Text(_formatDate(summary.createdAt), style: textTheme.bodySmall),
                              ],
                            ),
                          ),
                          if (loading)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  return "${local.year}/${local.month.toString().padLeft(2, "0")}/${local.day.toString().padLeft(2, "0")}";
}
