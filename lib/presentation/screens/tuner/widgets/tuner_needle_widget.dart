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
        TunerState.inTune   => AppColors.inTune,
        TunerState.nearTune => AppColors.primary,
        TunerState.tooLow   => AppColors.tooLow,
        TunerState.tooHigh  => AppColors.tooHigh,
        TunerState.silent   => AppColors.textDisabled,
      };

  @override
  Widget build(BuildContext context) {
    return BlocListener<TunerBloc, TunerDisplayState>(
      listener: (_, state) {
        final newTunerState =
            state is TunerListening ? state.pitch.state : TunerState.silent;
        final newTarget = state is TunerListening
            ? (state.pitch.centsDeviation.clamp(-50.0, 50.0) / 50.0) * (pi / 2)
            : 0.0;
        // setState forcé si l'état fonctionnel change — nécessaire pour la
        // transition inTune → silent quand l'aiguille est centrée (delta ≈ 0,
        // le Ticker ne déclencherait pas setState sans cette garde).
        if (_tunerState != newTunerState) {
          setState(() {
            _tunerState = newTunerState;
            _targetAngle = newTarget;
          });
        } else {
          _targetAngle = newTarget;
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
  // PF-08 : initialisés dans la liste d'initialisation — sémantique claire,
  // pas de lazy-init (late final) qui masquait le lien avec needleColor.
  _NeedlePainter({
    required this.displayAngle,
    required this.needleColor,
    required this.tunerState,
  })  : _needleLinePaint = Paint()
          ..color = needleColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
        _needleTipPaint = Paint()..color = needleColor;

  final double displayAngle;
  final Color needleColor;
  final TunerState tunerState;
  final Paint _needleLinePaint;
  final Paint _needleTipPaint;

  // Paints statiques — propriétés constantes, créés une seule fois pour toutes les instances.
  static final _arcPaint = Paint()
    ..color = AppColors.surfaceHigh
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  static final _inTunePaint = Paint()
    ..color = AppColors.inTune.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;

  static final _majorGradPaint = Paint()
    ..color = AppColors.textSecondary
    ..strokeWidth = 1.5;

  static final _minorGradPaint = Paint()
    ..color = AppColors.textDisabled
    ..strokeWidth = 1;

  static final _pivot1 = Paint()..color = AppColors.surfaceHigh;
  static final _pivot2 = Paint()..color = AppColors.divider;
  static final _pivot3 = Paint()..color = AppColors.textSecondary;

  // PF-07 : (cos, sin) des 11 graduations précomputés une seule fois.
  // Élimine 22 appels trig par frame — remplacés par des multiplications.
  static final List<({double cosA, double sinA, bool isMajor})> _gradData = [
    for (int i = -50; i <= 50; i += 10)
      (
        cosA: cos((3 * pi / 2) + (i / 50.0) * (pi / 2)),
        sinA: sin((3 * pi / 2) + (i / 50.0) * (pi / 2)),
        isMajor: i % 20 == 0,
      ),
  ];

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
      pi, pi, false, _arcPaint,
    );
  }

  // Arc vert ±2 cents autour du centre (dessiné avant l'aiguille = en dessous visuellement)
  void _drawInTuneZone(Canvas canvas, Offset center, double radius) {
    const halfAngle = (2.0 / 50.0) * (pi / 2); // 2 cents en radians
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      (3 * pi / 2) - halfAngle, // centre = 3π/2 (haut)
      halfAngle * 2,
      false,
      _inTunePaint,
    );
  }

  // Graduations toutes les 10 cents — (cos,sin) issus du cache statique _gradData
  void _drawGraduations(Canvas canvas, Offset center, double radius) {
    for (final g in _gradData) {
      final inner = radius - (g.isMajor ? 14.0 : 8.0);
      canvas.drawLine(
        Offset(center.dx + inner  * g.cosA, center.dy + inner  * g.sinA),
        Offset(center.dx + radius * g.cosA, center.dy + radius * g.sinA),
        g.isMajor ? _majorGradPaint : _minorGradPaint,
      );
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double len) {
    // drawingAngle = 3π/2 + displayAngle
    // displayAngle=0 → pointe vers le haut; -π/2 → gauche; +π/2 → droite
    final a = (3 * pi / 2) + displayAngle;
    final tip = Offset(center.dx + len * cos(a), center.dy + len * sin(a));
    canvas.drawLine(center, tip, _needleLinePaint);
    canvas.drawCircle(tip, 4, _needleTipPaint);
  }

  void _drawPivot(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 7, _pivot1);
    canvas.drawCircle(center, 5, _pivot2);
    canvas.drawCircle(center, 3, _pivot3);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.displayAngle != displayAngle ||
      old.needleColor != needleColor ||
      old.tunerState != tunerState;
}
