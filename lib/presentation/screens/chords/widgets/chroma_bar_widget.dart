import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/note_frequency_converter.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/chord_detector_bloc.dart';
import '../bloc/chord_state.dart';

/// Représentation visuelle du chromagramme (US3) : 12 barres, une par degré
/// chromatique (convention MIDI `C=0`, `NoteFrequencyConverter.chromaticScale`),
/// hauteur proportionnelle à l'intensité normalisée du degré, degrés actifs
/// (`ChordResult.activeNoteIndices`) mis en évidence.
class ChromaBarWidget extends StatelessWidget {
  const ChromaBarWidget({super.key});

  static const _empty = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChordDetectorBloc, ChordDisplayState>(
      buildWhen: (prev, next) {
        if (prev is! ChordListening || next is! ChordListening) {
          return prev.runtimeType != next.runtimeType;
        }
        return !listEquals(
              prev.smoothed.result.chromaVector,
              next.smoothed.result.chromaVector,
            ) ||
            !setEquals(
              prev.smoothed.result.activeNoteIndices,
              next.smoothed.result.activeNoteIndices,
            );
      },
      builder: (_, state) {
        final chroma = state is ChordListening
            ? state.smoothed.result.chromaVector
            : _empty;
        final active = state is ChordListening
            ? state.smoothed.result.activeNoteIndices
            : const <int>{};

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 96,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ChromaBarPainter(chroma: chroma, active: active),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (int i = 0; i < 12; i++)
                  Expanded(
                    child: Text(
                      NoteFrequencyConverter.chromaticScale[i],
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: active.contains(i)
                            ? AppColors.primary
                            : AppColors.textDisabled,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────

class _ChromaBarPainter extends CustomPainter {
  _ChromaBarPainter({required this.chroma, required this.active});

  final List<double> chroma;
  final Set<int> active;

  static const _gap = 4.0;
  static final _trackPaint = Paint()..color = AppColors.surfaceHigh;
  static final _activePaint = Paint()..color = AppColors.primary;
  static final _inactivePaint = Paint()..color = AppColors.secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (chroma.length != 12) return;
    final barWidth = (size.width - _gap * 11) / 12;

    for (int i = 0; i < 12; i++) {
      final left = i * (barWidth + _gap);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, barWidth, size.height),
          const Radius.circular(3),
        ),
        _trackPaint,
      );

      final intensity = chroma[i].clamp(0.0, 1.0);
      if (intensity <= 0.02) continue;

      final barHeight = size.height * intensity;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(3),
        ),
        active.contains(i) ? _activePaint : _inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChromaBarPainter old) =>
      !listEquals(old.chroma, chroma) || !setEquals(old.active, active);
}
