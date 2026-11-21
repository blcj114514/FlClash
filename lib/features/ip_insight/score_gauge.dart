import 'dart:math' as math;

import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';

Color purityColorOf(BuildContext context, IpPurityGrade grade) {
  final scheme = context.colorScheme;
  return switch (grade) {
    IpPurityGrade.pristine => scheme.success,
    IpPurityGrade.clean => Color.lerp(scheme.success, scheme.primary, 0.35)!,
    IpPurityGrade.moderate => scheme.warning,
    IpPurityGrade.polluted => Color.lerp(scheme.warning, scheme.error, 0.5)!,
    IpPurityGrade.severe => scheme.error,
  };
}

DashboardChipTone purityChipToneOf(IpPurityGrade grade) {
  return switch (grade) {
    IpPurityGrade.pristine || IpPurityGrade.clean => DashboardChipTone.ok,
    IpPurityGrade.moderate ||
    IpPurityGrade.polluted ||
    IpPurityGrade.severe => DashboardChipTone.warn,
  };
}

/// Animated circular purity score ring matching FlClash's M3 Expressive style.
class PurityScoreGauge extends StatelessWidget {
  const PurityScoreGauge({
    super.key,
    required this.score,
    required this.grade,
    this.size = 64,
    this.strokeWidth = 6,
    this.loading = false,
  });

  final int? score;
  final IpPurityGrade? grade;
  final double size;
  final double strokeWidth;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final scheme = context.colorScheme;
    final targetScore = (score ?? 0).clamp(0, 100);
    final progress = score == null ? 0.0 : targetScore / 100.0;
    final accent = grade != null
        ? purityColorOf(context, grade!)
        : scheme.primary;
    final trackColor = grade == IpPurityGrade.severe && targetScore <= 5
        ? accent.withValues(alpha: 0.24)
        : colors.tone2;
    final figureStyle = size >= 76
        ? AppTextStyle.title1
        : size >= 60
        ? AppTextStyle.title2
        : AppTextStyle.headline;

    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: context.motionDuration(const Duration(milliseconds: 520)),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final shown = score == null ? '—' : '${(value * 100).round()}';
        final paintProgress = score != null && targetScore <= 4
            ? 0.05
            : value;
        return SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _ScoreRingPainter(
              progress: paintProgress,
              trackColor: trackColor,
              accentColor: accent,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shown,
                    maxLines: 1,
                    style: DashboardText.figure(
                      context,
                      figureStyle,
                      color: score == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                  if (size >= 68)
                    Text(
                      loading ? '...' : '/100',
                      maxLines: 1,
                      style: DashboardText.label(context),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.progress,
    required this.trackColor,
    required this.accentColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color accentColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final sweep = (progress.clamp(0.0, 1.0)) * math.pi * 2;
    final arcPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
