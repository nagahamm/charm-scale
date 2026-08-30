import "dart:convert";

import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../models/person.dart";
import "../services/analysis_api.dart";
import "../services/auth_service.dart";
import "../services/image_prep.dart";
import "../theme.dart";
import "person_list_screen.dart";
import "result_screen.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _imagePrep = ImagePrepService();
  final _contextController = TextEditingController();

  AnalysisMode _mode = AnalysisMode.chat;
  final List<PickedImage> _images = [];
  final List<PickedImage> _partnerProfileImages = [];
  final List<PickedImage> _selfProfileImages = [];
  Person? _selectedPerson;
  bool _loading = false;
  String _status = "";

  List<PickedImage> get _profileImagesForMode =>
      _mode == AnalysisMode.chat ? _partnerProfileImages : _selfProfileImages;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  String get _imagesHint => switch (_mode) {
        AnalysisMode.chat => "トーク画面のスクショを時系列順に追加",
        AnalysisMode.photo => "1枚目がメイン写真になります。人物だけでなく、背景・食事などのサブ写真も追加できます",
      };

  Future<void> _addCameraTo(List<PickedImage> target) async {
    if (target.length >= maxImages) return;
    final picked = await _imagePrep.pickFromCamera();
    if (picked == null) return;
    setState(() => target.add(picked));
  }

  Future<void> _addGalleryTo(List<PickedImage> target) async {
    final remaining = maxImages - target.length;
    if (remaining <= 0) return;
    final picked = await _imagePrep.pickFromGallery(remainingSlots: remaining);
    setState(() => target.addAll(picked));
  }

  void _removeFrom(List<PickedImage> target, int index) => setState(() => target.removeAt(index));

  Future<void> _pickPerson() async {
    final person = await Navigator.of(context).push<Person>(
      MaterialPageRoute(builder: (_) => const PersonListScreen(pickMode: true)),
    );
    if (person != null && mounted) setState(() => _selectedPerson = person);
  }

  Future<void> _submit() async {
    if (_images.isEmpty) return;
    if (_mode == AnalysisMode.chat && _selectedPerson == null) return;
    setState(() {
      _loading = true;
      _status = "送信中…";
    });

    final service = AnalysisApiService();
    final acc = AnalysisAccumulator();
    try {
      await for (final event in service.stream(
        mode: _mode,
        images: _images,
        profileImages: _profileImagesForMode,
        context: _contextController.text,
        personId: _mode == AnalysisMode.chat ? _selectedPerson?.id : null,
      )) {
        acc.add(event);
        switch (event) {
          case StatusEvent(:final text):
            if (mounted) setState(() => _status = text);
          case ErrorEvent(:final message):
            throw AnalysisApiException(message);
          case DeltaEvent():
          case DoneEvent():
            break;
        }
      }

      final json = acc.buildJson();
      final result = switch (_mode) {
        AnalysisMode.chat => ChatResult.fromJson(json),
        AnalysisMode.photo => PhotoResult.fromJson(json),
      };

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(mode: _mode, result: result, images: _images)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AnalysisApiException ? e.message : "解析に失敗しました。")),
      );
    } finally {
      service.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("振り返り"),
        actions: [
          if (isSupabaseConfigured)
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: "相手一覧",
              onPressed: _loading
                  ? null
                  : () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PersonListScreen())),
            ),
          if (isSupabaseConfigured)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "ログアウト",
              onPressed: _loading ? null : AuthService().signOut,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SegmentedButton<AnalysisMode>(
              segments: const [
                ButtonSegment(value: AnalysisMode.chat, label: Text("会話")),
                ButtonSegment(value: AnalysisMode.photo, label: Text("写真")),
              ],
              selected: {_mode},
              onSelectionChanged: _loading
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            if (_mode == AnalysisMode.chat) ...[
              const SizedBox(height: AppSpacing.md),
              _PersonPickerCard(person: _selectedPerson, loading: _loading, onTap: _pickPerson),
            ],
            const SizedBox(height: AppSpacing.md),
            _ImagePickerSection(
              title: _mode == AnalysisMode.chat ? "トーク画面" : "評価する写真",
              hint: _imagesHint,
              images: _images,
              loading: _loading,
              showMainBadge: _mode == AnalysisMode.photo,
              onCamera: () => _addCameraTo(_images),
              onGallery: () => _addGalleryTo(_images),
              onRemove: (i) => _removeFrom(_images, i),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ImagePickerSection(
              title: _mode == AnalysisMode.chat ? "相手のプロフィール(任意)" : "自分のプロフィール(任意)",
              hint: _mode == AnalysisMode.chat
                  ? "年齢・職業・自己紹介などが見える画面を、会話と同じ人物の分だけ追加"
                  : "自己紹介文やいいね数が見える自分のプロフィール画面を追加",
              images: _profileImagesForMode,
              loading: _loading,
              onCamera: () => _addCameraTo(_profileImagesForMode),
              onGallery: () => _addGalleryTo(_profileImagesForMode),
              onRemove: (i) => _removeFrom(_profileImagesForMode, i),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _contextController,
              enabled: !_loading,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "補足情報(任意)",
                hintText: "相手の年齢層、これまでの経緯など",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _loading ||
                      _images.isEmpty ||
                      (_mode == AnalysisMode.chat && _selectedPerson == null)
                  ? null
                  : _submit,
              child: _loading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(_status),
                      ],
                    )
                  : const Text("分析する"),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonPickerCard extends StatelessWidget {
  final Person? person;
  final bool loading;
  final VoidCallback onTap;

  const _PersonPickerCard({required this.person, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  person == null ? "相手を選択(必須)" : person!.nickname,
                  style: textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePickerSection extends StatelessWidget {
  final String? title;
  final String hint;
  final List<PickedImage> images;
  final bool loading;
  final bool showMainBadge;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(int index) onRemove;

  const _ImagePickerSection({
    required this.title,
    required this.hint,
    required this.images,
    required this.loading,
    this.showMainBadge = false,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final full = images.length >= maxImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(hint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        _ImageGrid(images: images, onRemove: loading ? null : onRemove, showMainBadge: showMainBadge),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loading || full ? null : onCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text("カメラ"),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loading || full ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text("ライブラリ"),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<PickedImage> images;
  final void Function(int index)? onRemove;
  final bool showMainBadge;

  const _ImageGrid({required this.images, required this.onRemove, this.showMainBadge = false});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Text("画像が未選択です", style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < images.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                child: Image.memory(
                  const Base64Decoder().convert(images[i].base64Data),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              if (showMainBadge && i == 0)
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
              if (onRemove != null)
                Positioned(
                  right: -6,
                  top: -6,
                  child: IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.cancel, color: AppColors.textSecondary),
                    onPressed: () => onRemove!(i),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
