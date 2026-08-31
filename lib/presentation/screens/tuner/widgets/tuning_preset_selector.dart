import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/tuning_configuration.dart';
import '../../../../domain/entities/tuning_profile.dart';
import '../../../../domain/repositories/tuning_profile_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../bloc/tuner_bloc.dart';
import '../bloc/tuner_event.dart';
import '../bloc/tuner_state.dart';
import 'tuning_preset_chip.dart';

/// Sélecteur de profil d'accordage : bascule entre l'accordage standard et
/// les profils personnalisés sauvegardés (`TuningProfileRepository`), sans
/// interrompre l'écoute en cours — `ConfigChanged` passe par
/// `AudioRepository.updateConfig` (pas de redémarrage de l'Isolate/du
/// micro), cf. `TunerBloc._onConfigChanged`.
class TuningPresetSelector extends StatelessWidget {
  const TuningPresetSelector({super.key, required this.repository});

  final TuningProfileRepository repository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      buildWhen: (prev, next) {
        if (prev is! TunerListening || next is! TunerListening) {
          return prev.runtimeType != next.runtimeType;
        }
        return prev.config.presetId != next.config.presetId;
      },
      builder: (context, state) {
        final currentConfig = state is TunerListening
            ? state.config
            : TuningConfiguration.standard;

        return StreamBuilder<List<TuningProfile>>(
          stream: repository.watchAll(),
          builder: (context, snapshot) {
            final profiles = snapshot.data ?? const <TuningProfile>[];
            final label = _labelFor(currentConfig.presetId, profiles);

            return TuningPresetChip(
              label: label,
              onTap: () =>
                  _openPicker(context, profiles, currentConfig),
            );
          },
        );
      },
    );
  }

  String _labelFor(String? presetId, List<TuningProfile> profiles) {
    if (presetId == null) return 'Standard';
    for (final profile in profiles) {
      if (profile.id == presetId) return profile.name;
    }
    return 'Standard';
  }

  Future<void> _openPicker(
    BuildContext context,
    List<TuningProfile> profiles,
    TuningConfiguration currentConfig,
  ) async {
    final bloc = context.read<TunerBloc>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PresetTile(
                label: 'Standard',
                selected: currentConfig.presetId == null,
                onTap: () {
                  bloc.add(
                    ConfigChanged(
                      currentConfig.copyWith(
                        stringNotes: TuningConfiguration.standard.stringNotes,
                        instrumentType:
                            TuningConfiguration.standard.instrumentType,
                        clearPresetId: true,
                        clearTargetString: true,
                        intelliTunerActive: false,
                      ),
                    ),
                  );
                  Navigator.of(sheetContext).pop();
                },
              ),
              for (final profile in profiles)
                _PresetTile(
                  label: profile.name,
                  selected: profile.id == currentConfig.presetId,
                  onTap: () {
                    bloc.add(
                      ConfigChanged(
                        currentConfig.copyWith(
                          stringNotes: profile.stringNotes,
                          instrumentType: profile.instrumentType,
                          presetId: profile.id,
                          clearTargetString: true,
                          intelliTunerActive: false,
                        ),
                      ),
                    );
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: AppTextStyles.bodyLarge.copyWith(
          color: selected ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
  }
}
