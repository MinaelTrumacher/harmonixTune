import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/tuning_configuration.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_event.dart';
import '../bloc/tuner_state.dart';

// Config courante, qu'elle porte sur TunerListening (une hauteur a déjà été
// détectée) ou TunerInitial (pas encore, ex. juste après un changement de
// preset avant que le micro n'ait capté un premier son) — sans ce repli sur
// TunerInitial, un changement de preset appliqué trop tôt restait invisible.
TuningConfiguration? _configOf(TunerDisplayState state) => switch (state) {
  TunerListening(:final config) => config,
  TunerInitial(:final config) => config,
  _ => null,
};

class StringSelectorWidget extends StatelessWidget {
  const StringSelectorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      buildWhen: (prev, next) => _configOf(prev) != _configOf(next),
      builder: (_, state) {
        final config = _configOf(state);
        final strings =
            config?.stringNotes ?? const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
        final selected = config?.targetString;
        final isAuto = selected == null;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: strings.map((note) {
            final isSelected = note == selected;
            return GestureDetector(
              onTap: () => context.read<TunerBloc>().add(
                StringSelected(isSelected ? null : note),
              ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isAuto ? 0.4 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.surfaceHigh
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.divider,
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      note,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
