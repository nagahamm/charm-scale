import "package:flutter/material.dart";
import "package:flutter/services.dart";

class CopyButton extends StatelessWidget {
  final String text;

  const CopyButton({super.key, required this.text});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("コピーしました"), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy_outlined, size: 20),
      tooltip: "コピー",
      onPressed: () => _copy(context),
    );
  }
}
