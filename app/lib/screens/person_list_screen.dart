import "package:flutter/material.dart";

import "../models/person.dart";
import "../services/history_api.dart";
import "../theme.dart";
import "person_history_screen.dart";

/// 相手(Person)の一覧。pickMode が true の場合はカードをタップすると
/// その Person で Navigator.pop する(会話モードの相手選択で使う)。
/// pickMode が false の場合は履歴画面(PersonHistoryScreen)へ遷移する。
class PersonListScreen extends StatefulWidget {
  final bool pickMode;
  const PersonListScreen({super.key, this.pickMode = false});

  @override
  State<PersonListScreen> createState() => _PersonListScreenState();
}

class _PersonListScreenState extends State<PersonListScreen> {
  final _api = HistoryApiService();
  late Future<List<Person>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchPersons();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = _api.fetchPersons();
    setState(() => _future = future);
    await future;
  }

  Future<void> _createPerson() async {
    final controller = TextEditingController();
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("相手を追加"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(labelText: "ニックネーム"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("キャンセル")),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text("追加"),
          ),
        ],
      ),
    );
    if (nickname == null || nickname.isEmpty || !mounted) return;

    try {
      await _api.createPerson(nickname);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is HistoryApiException ? e.message : "追加に失敗しました。")),
      );
    }
  }

  Future<void> _deletePerson(Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${person.nickname}を削除しますか?"),
        content: const Text("紐づく分析結果もすべて削除されます。"),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("キャンセル")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("削除")),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _api.deletePerson(person.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is HistoryApiException ? e.message : "削除に失敗しました。")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? "相手を選択" : "相手一覧"),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_alt), onPressed: _createPerson),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<Person>>(
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
              final persons = snapshot.data ?? const [];
              if (persons.isEmpty) {
                return ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text("まだ相手が登録されていません。右上から追加できます。", textAlign: TextAlign.center),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: persons.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) => _PersonCard(
                  person: persons[index],
                  onTap: () {
                    if (widget.pickMode) {
                      Navigator.of(context).pop(persons[index]);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PersonHistoryScreen(person: persons[index])),
                      );
                    }
                  },
                  onDelete: () => _deletePerson(persons[index]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final Person person;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PersonCard({required this.person, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final latest = person.latest;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.nickname, style: textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    if (latest != null) ...[
                      Row(
                        children: [
                          if (latest.interestScore != null)
                            Text(
                              "食いつき度数 ${latest.interestScore}",
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.forScore(latest.interestScore!),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (latest.phase != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(latest.phase!, style: textTheme.bodySmall),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(latest.headline, style: textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ] else
                      Text("まだ分析がありません", style: textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
