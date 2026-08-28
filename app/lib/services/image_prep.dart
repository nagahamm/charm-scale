import "dart:convert";

import "package:image_picker/image_picker.dart";

/// api/functions/analyse.mjs の MAX_IMAGES と揃える。
const maxImages = 8;

/// 長辺をこのサイズまで縮小してからアップロードする。
const _maxEdge = 1568.0;

class PickedImage {
  final String mediaType;
  final String base64Data;

  const PickedImage({required this.mediaType, required this.base64Data});

  Map<String, String> toJson() => {"media_type": mediaType, "data": base64Data};
}

class ImagePrepService {
  final ImagePicker _picker = ImagePicker();

  Future<PickedImage?> pickFromCamera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: 85,
    );
    if (file == null) return null;
    return _toPickedImage(file);
  }

  Future<List<PickedImage>> pickFromGallery({required int remainingSlots}) async {
    if (remainingSlots <= 0) return const [];
    final files = await _picker.pickMultiImage(
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: 85,
      limit: remainingSlots,
    );
    final results = <PickedImage>[];
    for (final file in files) {
      results.add(await _toPickedImage(file));
    }
    return results;
  }

  Future<PickedImage> _toPickedImage(XFile file) async {
    final bytes = await file.readAsBytes();
    return PickedImage(
      mediaType: _mediaTypeOf(file),
      base64Data: base64Encode(bytes),
    );
  }

  String _mediaTypeOf(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith("image/")) return mime;

    final name = file.name.toLowerCase();
    if (name.endsWith(".png")) return "image/png";
    if (name.endsWith(".webp")) return "image/webp";
    if (name.endsWith(".gif")) return "image/gif";
    return "image/jpeg";
  }
}
