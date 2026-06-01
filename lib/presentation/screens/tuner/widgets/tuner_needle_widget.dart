import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/enums/tuner_state.dart';
import '../../../theme/app_colors.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_state.dart';

class TunerNeedleWidget extends StatefulWidget {
  const TunerNeedleWidget({super.key});

  @override
  State<TunerNeedleWidget> createState() => _TunerNeedleWidgetState();
}

class _TunerNeedleWidgetState extends State<TunerNeedleWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // Angle courant dessiné — interpolé chaque frame
  double _displayAngle = 0.0;
  // Angle cible — mis à jour par le stream BLoC (hors vsync)
  double _targetAngle = 0.0;
  TunerState _tunerState = TunerState.silent;

  // alpha = 0.25 : suivi réactif sans tremblement sur notes instables
  static const double _alpha = 0.25;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final next = _displayAngle + _alpha * (_targetAngle - _displayAngle);
      if ((next - _displayAngle).abs() > 0.0001) {
        setState(() => _displayAngle = next);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color _needleColor(TunerState state) => switch (state) {
        TunerState.inTune  => AppColors.inTune,
        TunerState.tooLow  => AppColors.tooLow,
        TunerState.tooHigh => AppColors.tooHigh,
        TunerState.silent  => AppColors.textDisabled,
      };

  @override
  Widget build(BuildContext context) {
    return BlocListener<TunerBloc, TunerDisplayState>(
      listener: (_, state) {
        if (state is TunerListening) {
          // centsDeviation ∈ [-50, 50] → _targetAngle ∈ [-π/2, π/2]
          _targetAngle =
              (state.pitch.centsDeviation.clamp(-50.0, 50.0) / 50.0) * (pi / 2);
          _tunerState = state.pitch.state;
        } else {
          _targetAngle = 0.0;
          _tunerState = TunerState.silent;
        }
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _NeedlePainter(
            displayAngle: _displayAngle,
            needleColor: _needleColor(_tunerState),
            tunerState: _tunerState,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter({
    required this.displayAngle,
    required this.needleColor,
    required this.tunerState,
  });

  final double displayAngle;
  final Color needleColor;
  final TunerState tunerState;

  @override
  void paint(Canvas canvas, Size size) {
    // Pivot au centre-bas du widget
    final center = Offset(size.width / 2, size.height);
    final radius = (min(size.width / 2 - 16, size.height - 8)).toDouble();
    final needleLen = radius * 0.84;

    _drawArc(canvas, center, radius);
    _drawInTuneZone(canvas, center, radius);
    _drawGraduations(canvas, center, radius);
    _drawNeedle(canvas, center, needleLen);
    _drawPivot(canvas, center);
  }

  // Arc de fond demi-cercle (ouest → nord → est)
  // startAngle = π, sweepAngle = π → sens horaire en coords canvas (y-bas) = par le haut ✓
  void _drawArc(Canvas canvas, Offset center, double radius) {
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi, pi, false,
      Paint()
        ..color = AppColors.surfaceHigh
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  // Arc vert ±2 cents autour du centre (sous l'aiguille)
  void _drawInTuneZone(Canvas canvas, Offset center, double radius) {
    const halfAngle = (2.0 / 50.0) * (pi / 2); // 2 cents en radians
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      (3 * pi / 2) - halfAngle, // centre = 3π/2 (haut)
      halfAngle * 2,
      false,
      Paint()
        ..color = AppColors.inTune.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  // Graduations toutes les 10 cents, labels -50/-25/0/+25/+50
  void _drawGraduations(Canvas canvas, Offset center, double radius) {
    final majorPaint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1.5;
    final minorPaint = Paint()
      ..color = AppColors.textDisabled
      ..strokeWidth = 1;

    for (int i = -50; i <= 50; i += 10) {
      final a = (3 * pi / 2) + (i / 50.0) * (pi / 2);
      final isMajor = i % 20 == 0;
      final inner = radius - (isMajor ? 14.0 : 8.0);
      canvas.drawLine(
        Offset(center.dx + inner * cos(a), center.dy + inner * sin(a)),
        Offset(center.dx + radius * cos(a), center.dy + radius * sin(a)),
        isMajor ? majorPaint : minorPaint,
      );
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double len) {
    // drawingAngle = 3π/2 + displayAngle
    // displayAngle=0 → pointe vers le haut; -π/2 → gauche; +π/2 → droite
    final a = (3 * pi / 2) + displayAngle;
    final tip = Offset(center.dx + len * cos(a), center.dy + len * sin(a));

    canvas.drawLine(
      center, tip,
      Paint()
        ..color = needleColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    // Embout de l'aiguille
    canvas.drawCircle(tip, 4, Paint()..color = needleColor);
  }

  void _drawPivot(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 7, Paint()..color = AppColors.surfaceHigh);
    canvas.drawCircle(center, 5, Paint()..color = AppColors.divider);
    canvas.drawCircle(center, 3, Paint()..color = AppColors.textSecondary);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.displayAngle != displayAngle ||
      old.needleColor != needleColor ||
      old.tunerState != tunerState;
}
