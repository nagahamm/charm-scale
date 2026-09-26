import "package:flutter/material.dart";

import "../models/person.dart";
import "../services/history_api.dart";
import "../theme.dart";
import "../widgets/trend_chart.dart";
import "home_screen.dart";
import "person_thread_screen.dart";

/// 特定の Person(相手)の履歴画面(docs/requirements.md 3.3節)。
/// 個別の分析結果を読み返す手段は無く、通し会話(#22)に一本化している。
class PersonHistoryScreen extends StatefulWidget {
  final Person person;
  const PersonHistoryScreen({super.key, required this.person});

  @override
  State<PersonHistoryScreen> createState() => _PersonHistoryScreenState();
}

class _PersonHistoryScreenState extends State<PersonHistoryScreen> {
  final _api = HistoryApiService();
  late Future<List<AnalysisSummary>> _future;
  bool _continuing = false;

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

  /// 直前の分析の要約を引き継いで、続きのスクショで分析する(docs/requirements.md 3.3節)。
  Future<void> _continueFromLatest(List<AnalysisSummary> analyses) async {
    setState(() => _continuing = true);
    try {
      final latest = await _api.fetchChatDetail(latestOf(analyses).id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HomeScreen(continuingPerson: widget.person, previousSummary: latest.summary),
        ),
      );
      if (!mounted) return;
      // 新しい分析が一覧・推移グラフに反映されるよう取り直す。
      setState(() => _future = _api.fetchAnalyses(widget.person.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is HistoryApiException ? e.message : "読み込みに失敗しました。")),
      );
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.person.nickname)),
      body: SafeArea(
        child: Column(
          children: [
            _MemoSection(person: widget.person, api: _api),
            Expanded(
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
                    return const Center(
                      child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text("まだ分析がありません。")),
                    );
                  }
                  final scored = scoredInOrder(analyses);
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      _ViewConversationButton(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PersonThreadScreen(person: widget.person)),
                        ),
                      ),
                      if (scored.length >= 2) ...[
                        const SizedBox(height: AppSpacing.md),
                        _TrendSection(analyses: scored),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: _continuing ? null : () => _continueFromLatest(analyses),
                        icon: _continuing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text("続きのスクショで分析"),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 会話を見る(#20の通し会話への入口)。埋もれないよう、履歴画面の主要な導線として
/// 大きく表示する(docs/requirements.md 3.3節「会話を見る導線をすぐ見つけられる」、#22)。
class _ViewConversationButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewConversationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: AppColors.primary,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.forum, color: Colors.white, size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "会話を見る",
                      style: textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "これまでのやり取りをまとめて振り返る",
                      style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最新の分析(APIのレスポンス順に依存せず created_at で判断する)。
AnalysisSummary latestOf(List<AnalysisSummary> analyses) =>
    analyses.reduce((a, b) => b.createdAt.isAfter(a.createdAt) ? b : a);

/// 食いつき度数を持つ分析だけを、古い順に並べ替えて返す(推移グラフ用)。
/// APIのレスポンス順に依存しないよう created_at で整列する。
List<AnalysisSummary> scoredInOrder(List<AnalysisSummary> analyses) =>
    analyses.where((a) => a.interestScore != null).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// 分析をまたいだ食いつき度数の推移(docs/requirements.md 3.3節)。
class _TrendSection extends StatelessWidget {
  final List<AnalysisSummary> analyses;

  const _TrendSection({required this.analyses});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("食いつき度数の推移", style: textTheme.titleMedium),
            TrendChart(values: [for (final a in analyses) a.interestScore!]),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDate(analyses.first.createdAt), style: textTheme.bodySmall),
                Text(_formatDate(analyses.last.createdAt), style: textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 相手単位の振り返りメモ(docs/requirements.md 3.3節「自分の反省メモ」、#21)。
/// AIが生成する内容とは別に、利用者自身が書いた文章をそのまま保存する。
class _MemoSection extends StatefulWidget {
  final Person person;
  final HistoryApiService api;

  const _MemoSection({required this.person, required this.api});

  @override
  State<_MemoSection> createState() => _MemoSectionState();
}

class _MemoSectionState extends State<_MemoSection> {
  late final TextEditingController _controller = TextEditingController(text: widget.person.memo);
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.updatePersonMemo(widget.person.id, _controller.text.trim());
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is HistoryApiException ? e.message : "保存に失敗しました。")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("自分のメモ", style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _controller,
                maxLines: 3,
                enabled: !_saving,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: const InputDecoration(
                  hintText: "振り返りを書き留める(例: 重い話題を早く振りすぎた)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: (_saving || !_dirty) ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("保存"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  return "${local.year}/${local.month.toString().padLeft(2, "0")}/${local.day.toString().padLeft(2, "0")}";
}
