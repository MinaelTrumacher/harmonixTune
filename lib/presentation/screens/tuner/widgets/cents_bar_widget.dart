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
    TunerState.inTune => AppColors.inTune,
    TunerState.nearTune => AppColors.primary,
    TunerState.tooLow => AppColors.tooLow,
    TunerState.tooHigh => AppColors.tooHigh,
    TunerState.silent => AppColors.textDisabled,
  };

  @override
  Widget build(BuildContext context) {
    return BlocListener<TunerBloc, TunerDisplayState>(
      listener: (_, state) {
        final newTunerState = state is TunerListening
            ? state.pitch.state
            : TunerState.silent;
        final newTarget = state is TunerListening
            ? state.pitch.centsDeviation.clamp(-50.0, 50.0)
            : 0.0;
        // setState forcé si l'état fonctionnel change — symétrique avec
        // TunerNeedleWidget (F-02) : la bille ne peut pas rester verte
        // quand l'utilisateur arrête de jouer, bille centrée, delta ≈ 0.
        if (_tunerState != newTunerState) {
          setState(() {
            _tunerState = newTunerState;
            _targetCents = newTarget;
          });
        } else {
          _targetCents = newTarget;
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
  _CentsBarPainter({
    required this.centsDeviation,
    required this.indicatorColor,
  });

  final double centsDeviation;
  final Color indicatorColor;

  // Shader du gradient — recréé uniquement si la largeur du widget change.
  // Couleurs pré-calculées (withValues non utilisable en const).
  static const _gradientColors = [
    Color(0x995B8EF0), // AppColors.tooLow  @ alpha 0.6
    AppColors.surfaceHigh,
    Color(0x99F06050), // AppColors.tooHigh @ alpha 0.6
  ];
  static Shader? _barShader;
  static Paint? _barPaint;
  static double _cachedBarWidth = -1;
  static double _cachedBarHeight = -1;

  // Paints statiques — jamais modifiés après init.
  static final _centerLinePaint = Paint()
    ..color = AppColors.textSecondary
    ..strokeWidth = 1.5;

  // Paints dynamiques liés à indicatorColor — recalculés uniquement lors d'un
  // changement de TunerState (rare), pas à chaque frame.
  static Color _lastIndicatorColor = const Color(0x00000000);
  static Paint? _haloPaint;
  static Paint? _ballPaint;

  @override
  void paint(Canvas canvas, Size size) {
    const ballRadius = 8.0;
    final barY = size.height / 2;
    final barLeft = ballRadius;
    final barWidth = size.width - 2 * ballRadius;

    // ── Gradient bar ─────────────────────────────────────────────────────
    // Shader et Paint recréés uniquement si la taille du widget change.
    // barY dépend de size.height → les deux dimensions sont dans la clé.
    if (barWidth != _cachedBarWidth || size.height != _cachedBarHeight) {
      _barShader = const LinearGradient(
        colors: _gradientColors,
      ).createShader(Rect.fromLTWH(barLeft, barY - 2, barWidth, 4));
      _barPaint = Paint()..shader = _barShader;
      _cachedBarWidth = barWidth;
      _cachedBarHeight = size.height;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barY - 2, barWidth, 4),
        const Radius.circular(2),
      ),
      _barPaint!,
    );

    // ── Marque centrale ───────────────────────────────────────────────────
    canvas.drawLine(
      Offset(size.width / 2, barY - 9),
      Offset(size.width / 2, barY + 9),
      _centerLinePaint,
    );

    // ── Bille indicatrice ─────────────────────────────────────────────────
    if (indicatorColor != _lastIndicatorColor) {
      _haloPaint = Paint()..color = indicatorColor.withValues(alpha: 0.18);
      _ballPaint = Paint()..color = indicatorColor;
      _lastIndicatorColor = indicatorColor;
    }

    final t = (centsDeviation + 50) / 100.0; // 0.0 → 1.0
    final x = barLeft + barWidth * t;

    canvas.drawCircle(Offset(x, barY), ballRadius + 4, _haloPaint!);
    canvas.drawCircle(Offset(x, barY), ballRadius, _ballPaint!);
  }

  @override
  bool shouldRepaint(_CentsBarPainter old) =>
      old.centsDeviation != centsDeviation ||
      old.indicatorColor != indicatorColor;
}
