import "package:flutter/material.dart";

import "../theme.dart";

/// 0〜100 のスコアの推移を折れ線で表示する。会話の中の推移(timeline)にも、
/// 分析をまたいだ推移(履歴画面)にも使う。並び順・値の抽出は呼び出し側の責務。
class TrendChart extends StatelessWidget {
  final List<int> values;
  final double height;

  const TrendChart({super.key, required this.values, this.height = 140});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _TrendPainter(values: values),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<int> values;

  const _TrendPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 12.0;
    const bottomPad = 12.0;
    final plotHeight = size.height - topPad - bottomPad;
    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;

    Offset pointAt(int i) {
      final x = stepX * i;
      final y = topPad + plotHeight * (1 - values[i] / 100);
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final level in [0, 50, 100]) {
      final y = topPad + plotHeight * (1 - level / 100);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < values.length; i++) {
      final p = pointAt(i);
      final dotColor = AppColors.forScore(values[i]);
      canvas.drawCircle(p, 3.5, Paint()..color = dotColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.values != values;
}
