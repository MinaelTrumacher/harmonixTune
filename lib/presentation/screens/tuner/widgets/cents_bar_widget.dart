import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/enums/tuner_state.dart';
import '../../../theme/app_colors.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_state.dart';

class CentsBarWidget extends StatefulWidget {
  const CentsBarWidget({super.key});

  @override
  State<CentsBarWidget> createState() => _CentsBarWidgetState();
}

class _CentsBarWidgetState extends State<CentsBarWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  double _displayCents = 0.0;
  double _targetCents = 0.0;
  TunerState _tunerState = TunerState.silent;

  static const double _alpha = 0.25;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final next = _displayCents + _alpha * (_targetCents - _displayCents);
      if ((next - _displayCents).abs() > 0.005) {
        setState(() => _displayCents = next);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color _stateColor(TunerState s) => switch (s) {
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
          _targetCents = state.pitch.centsDeviation.clamp(-50.0, 50.0);
          _tunerState = state.pitch.state;
        } else {
          _targetCents = 0.0;
          _tunerState = TunerState.silent;
        }
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CentsBarPainter(
            centsDeviation: _displayCents,
            indicatorColor: _stateColor(_tunerState),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────

class _CentsBarPainter extends CustomPainter {
  const _CentsBarPainter({
    required this.centsDeviation,
    required this.indicatorColor,
  });

  final double centsDeviation;
  final Color indicatorColor;

  @override
  void paint(Canvas canvas, Size size) {
    const ballRadius = 8.0;
    final barY = size.height / 2;
    final barLeft = ballRadius;
    final barRight = size.width - ballRadius;
    final barWidth = barRight - barLeft;

    // Barre de fond — gradient bleu → gris → rouge
    final shader = LinearGradient(
      colors: [
        AppColors.tooLow.withValues(alpha: 0.6),
        AppColors.surfaceHigh,
        AppColors.tooHigh.withValues(alpha: 0.6),
      ],
    ).createShader(Rect.fromLTWH(barLeft, barY - 2, barWidth, 4));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barY - 2, barWidth, 4),
        const Radius.circular(2),
      ),
      Paint()..shader = shader,
    );

    // Marque centrale (0 cents)
    canvas.drawLine(
      Offset(size.width / 2, barY - 9),
      Offset(size.width / 2, barY + 9),
      Paint()
        ..color = AppColors.textSecondary
        ..strokeWidth = 1.5,
    );

    // Bille indicatrice
    final t = (centsDeviation + 50) / 100.0; // 0.0 → 1.0
    final x = barLeft + barWidth * t;

    // Halo
    canvas.drawCircle(
      Offset(x, barY), ballRadius + 4,
      Paint()..color = indicatorColor.withValues(alpha: 0.18),
    );
    // Bille principale
    canvas.drawCircle(
      Offset(x, barY), ballRadius,
      Paint()..color = indicatorColor,
    );
  }

  @override
  bool shouldRepaint(_CentsBarPainter old) =>
      old.centsDeviation != centsDeviation ||
      old.indicatorColor != indicatorColor;
}
