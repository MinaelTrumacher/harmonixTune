import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_state.dart';

class NoteDisplayWidget extends StatelessWidget {
  const NoteDisplayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      buildWhen: (prev, next) {
        if (prev.runtimeType != next.runtimeType) return true;
        if (prev is! TunerListening || next is! TunerListening) return true;
        final p = prev.pitch;
        final n = next.pitch;
        // Rebuild uniquement si une valeur affichée change.
        return p.noteName != n.noteName ||
            p.octave != n.octave ||
            p.state != n.state ||
            p.frequencyHz.toStringAsFixed(1) !=
                n.frequencyHz.toStringAsFixed(1);
      },
      builder: (_, state) {
        final noteName = state is TunerListening ? state.pitch.noteName : '--';
        final octave = state is TunerListening ? '${state.pitch.octave}' : '';
        final hz = state is TunerListening
            ? '${state.pitch.frequencyHz.toStringAsFixed(1)} Hz'
            : '--- Hz';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noteName, style: AppTextStyles.displayLarge),
                if (octave.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4),
                    child: Text(
                      octave,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hz,
              style: AppTextStyles.mono.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        );
      },
    );
  }
}
