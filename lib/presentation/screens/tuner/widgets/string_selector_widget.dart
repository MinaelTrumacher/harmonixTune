import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_event.dart';
import '../bloc/tuner_state.dart';

class StringSelectorWidget extends StatelessWidget {
  const StringSelectorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      builder: (_, state) {
        final config   = state is TunerListening ? state.config : null;
        final strings  = config?.stringNotes ?? const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
        final selected = config?.targetString;
        final isAuto   = selected == null;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: strings.map((note) {
            final isSelected = note == selected;
            return GestureDetector(
              onTap: isAuto
                  ? null
                  : () => context.read<TunerBloc>().add(StringSelected(
                        isSelected ? null : note,
                      )),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isAuto ? 0.4 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.surfaceHigh : Colors.transparent,
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
