import "dart:convert";

import "package:flutter/material.dart";

import "../models/analysis.dart";
import "../services/analysis_api.dart";
import "../services/image_prep.dart";
import "../theme.dart";
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
  bool _loading = false;
  String _status = "";

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  String get _modeHint => switch (_mode) {
        AnalysisMode.chat => "トーク画面のスクショを時系列順に追加",
        AnalysisMode.photo => "評価したいプロフィール写真を追加",
        AnalysisMode.profile => "相手のプロフィール画面のスクショを追加",
      };

  Future<void> _addFromCamera() async {
    if (_images.length >= maxImages) return;
    final picked = await _imagePrep.pickFromCamera();
    if (picked == null) return;
    setState(() => _images.add(picked));
  }

  Future<void> _addFromGallery() async {
    final remaining = maxImages - _images.length;
    if (remaining <= 0) return;
    final picked = await _imagePrep.pickFromGallery(remainingSlots: remaining);
    setState(() => _images.addAll(picked));
  }

  void _removeAt(int index) => setState(() => _images.removeAt(index));

  Future<void> _submit() async {
    if (_images.isEmpty) return;
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
        context: _contextController.text,
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
        AnalysisMode.profile => ProfileResult.fromJson(json),
      };

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(mode: _mode, result: result)),
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
      appBar: AppBar(title: const Text("振り返り")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SegmentedButton<AnalysisMode>(
              segments: const [
                ButtonSegment(value: AnalysisMode.chat, label: Text("会話")),
                ButtonSegment(value: AnalysisMode.photo, label: Text("写真")),
                ButtonSegment(value: AnalysisMode.profile, label: Text("プロフィール")),
              ],
              selected: {_mode},
              onSelectionChanged: _loading
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(_modeHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            _ImageGrid(images: _images, onRemove: _loading ? null : _removeAt),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading || _images.length >= maxImages ? null : _addFromCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text("カメラ"),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading || _images.length >= maxImages ? null : _addFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("ライブラリ"),
                  ),
                ),
              ],
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
              onPressed: _loading || _images.isEmpty ? null : _submit,
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

class _ImageGrid extends StatelessWidget {
  final List<PickedImage> images;
  final void Function(int index)? onRemove;

  const _ImageGrid({required this.images, required this.onRemove});

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
