import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_event.dart';
import '../bloc/tuner_state.dart';

class IntelliTunerToggle extends StatelessWidget {
  const IntelliTunerToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      buildWhen: (prev, next) {
        // Rebuild uniquement si l'état du toggle change.
        return (prev is TunerListening && prev.intelliTunerEnabled) !=
               (next is TunerListening && next.intelliTunerEnabled);
      },
      builder: (_, state) {
        final enabled = state is TunerListening && state.intelliTunerEnabled;

        return Tooltip(
          message: 'Isole la fréquence de la corde sélectionnée — idéal en répétition',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 16,
                color: enabled ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Intelli-Tuner',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: 13,
                  color: enabled ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) => context
                    .read<TunerBloc>()
                    .add(IntelliTunerToggled(enabled: v)),
              ),
            ],
          ),
        );
      },
    );
  }
}
