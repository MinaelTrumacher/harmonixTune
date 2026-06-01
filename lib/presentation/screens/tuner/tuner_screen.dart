import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import '../../../data/datasources/record_microphone_data_source.dart';
import '../../../data/repositories/audio_repository_impl.dart';
import '../../shared/app_header.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'bloc/tuner_bloc.dart';
import 'bloc/tuner_event.dart';
import 'bloc/tuner_state.dart';
import 'widgets/cents_bar_widget.dart';
import 'widgets/intelli_tuner_toggle.dart';
import 'widgets/note_display_widget.dart';
import 'widgets/string_selector_widget.dart';
import 'widgets/tuner_needle_widget.dart';
import 'widgets/tuning_preset_chip.dart';

// Clé de comparaison pour le buildWhen du label de cents.
// Retourne la chaîne affichée — rebuild uniquement si elle change.
String _centsLabel(TunerDisplayState state) {
  if (state is! TunerListening) return '';
  final cents = state.pitch.centsDeviation;
  return cents.abs() < 0.5 ? 'tune' : cents.toStringAsFixed(1);
}

class TunerScreen extends StatelessWidget {
  const TunerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TunerBloc(
        AudioRepositoryImpl(RecordMicrophoneDataSource()),
      )..add(const StartTuner()),
      child: const _TunerView(),
    );
  }
}

class _TunerView extends StatelessWidget {
  const _TunerView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      buildWhen: (prev, next) =>
          (prev is TunerPermissionDeniedState) !=
          (next is TunerPermissionDeniedState),
      builder: (context, state) {
        if (state is TunerPermissionDeniedState) {
          return _PermissionDeniedView(isPermanent: state.isPermanent);
        }
        return const _TunerContent();
      },
    );
  }
}

// ── Vue de refus de permission (Scénario A1) ──────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({required this.isPermanent});

  final bool isPermanent;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_off_outlined, size: 64, color: AppColors.textDisabled),
            const Gap(24),
            Text(
              'Accès au microphone requis',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(12),
            Text(
              'L\'accordeur a besoin du microphone pour détecter les notes '
              'jouées par votre instrument.',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const Gap(32),
            if (isPermanent)
              FilledButton.icon(
                onPressed: () => AppSettings.openAppSettings(),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Ouvrir les réglages'),
              )
            else
              FilledButton.icon(
                onPressed: () =>
                    context.read<TunerBloc>().add(const StartTuner()),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Réessayer'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Contenu principal de l'accordeur ─────────────────────────────────────────

class _TunerContent extends StatelessWidget {
  const _TunerContent();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          const AppHeader(),

          // ── Preset + Instrument ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                TuningPresetChip(label: 'Standard', onTap: () {}),
                const Gap(8),
                TuningPresetChip(label: 'Guitar', onTap: () {}),
              ],
            ),
          ),

          const Gap(12),

          // ── Intelli-Tuner toggle ─────────────────────────────────────────
          const IntelliTunerToggle(),

          const Gap(8),

          // ── Cadran ───────────────────────────────────────────────────────
          SizedBox(
            height: 190,
            width: double.infinity,
            child: const TunerNeedleWidget(),
          ),

          const Gap(12),

          // ── Note + Hz ────────────────────────────────────────────────────
          const NoteDisplayWidget(),

          const Gap(20),

          // ── Barre de cents ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: CentsBarWidget(),
                ),
                const Gap(6),
                BlocBuilder<TunerBloc, TunerDisplayState>(
                  buildWhen: (prev, next) {
                    // Rebuild uniquement si le texte affiché change.
                    return _centsLabel(prev) != _centsLabel(next);
                  },
                  builder: (_, state) {
                    if (state is! TunerListening) {
                      return const SizedBox.shrink();
                    }
                    final cents = state.pitch.centsDeviation;
                    final isInTune = cents.abs() < 0.5;
                    return Text(
                      isInTune
                          ? '✓  IN TUNE'
                          : '${cents > 0 ? '+' : ''}${cents.toStringAsFixed(1)} cents',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isInTune
                            ? AppColors.inTune
                            : AppColors.textSecondary,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const Gap(24),

          // ── Sélecteur de cordes ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const StringSelectorWidget(),
          ),

          const Spacer(),

          // ── Slider de debug (mode debug uniquement) ──────────────────────
          if (kDebugMode) const _DebugCentsSlider(),

          const Gap(8),
        ],
      ),
    );
  }
}

// ── Debug only ─────────────────────────────────────────────────────────────

class _DebugCentsSlider extends StatelessWidget {
  const _DebugCentsSlider();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TunerBloc, TunerDisplayState>(
      builder: (context, state) {
        final cents = state is TunerListening
            ? state.pitch.centsDeviation.clamp(-50.0, 50.0)
            : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Text(
                'DEBUG  ${cents > 0 ? '+' : ''}${cents.toStringAsFixed(1)} ¢',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textDisabled,
                ),
              ),
              Slider(
                value: cents,
                min: -50,
                max: 50,
                divisions: 100,
                onChanged: (v) =>
                    context.read<TunerBloc>().add(DebugCentsOverride(v)),
                onChangeEnd: (_) =>
                    context.read<TunerBloc>().add(const StartTuner()),
              ),
            ],
          ),
        );
      },
    );
  }
}
