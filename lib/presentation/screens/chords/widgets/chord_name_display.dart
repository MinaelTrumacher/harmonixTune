import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/chord_detector_bloc.dart';
import '../bloc/chord_smoother.dart';
import '../bloc/chord_state.dart';

class ChordNameDisplay extends StatelessWidget {
  const ChordNameDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChordDetectorBloc, ChordDisplayState>(
      buildWhen: (prev, next) {
        if (prev is! ChordListening || next is! ChordListening) {
          return prev.runtimeType != next.runtimeType;
        }
        return prev.smoothed.kind != next.smoothed.kind ||
            prev.smoothed.result.chordName != next.smoothed.result.chordName;
      },
      builder: (_, state) {
        if (state is! ChordListening) return const _Placeholder();

        return switch (state.smoothed.kind) {
          SmoothedChordKind.silent => const _Placeholder(
            hint: 'Jouez un accord',
          ),
          SmoothedChordKind.indeterminate => _Label(
            text: '?',
            hint: 'Indéterminé',
            color: AppColors.textSecondary,
          ),
          SmoothedChordKind.detected => _Label(
            text: state.smoothed.result.chordName,
            hint:
                '${(state.smoothed.result.confidence * 100).round()}% de confiance',
            color: AppColors.primary,
          ),
        };
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.hint = 'En attente…'});

  final String hint;

  @override
  Widget build(BuildContext context) =>
      _Label(text: '--', hint: hint, color: AppColors.textDisabled);
}

class _Label extends StatelessWidget {
  const _Label({required this.text, required this.hint, required this.color});

  final String text;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: AppTextStyles.displayLarge.copyWith(color: color)),
        const SizedBox(height: 4),
        Text(
          hint,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
