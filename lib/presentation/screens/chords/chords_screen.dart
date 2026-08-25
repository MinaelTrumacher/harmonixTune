import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

import '../../../data/datasources/record_microphone_data_source.dart';
import '../../../data/repositories/chord_repository_impl.dart';
import '../../shared/app_header.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'bloc/chord_detector_bloc.dart';
import 'bloc/chord_event.dart';
import 'bloc/chord_state.dart';
import 'widgets/chord_name_display.dart';
import 'widgets/chroma_bar_widget.dart';

// Injection par constructeur (même principe que `TunerScreen`) : permet aux
// tests widget d'injecter un bloc/repo fake sans passer par un vrai
// microphone.
class ChordsScreen extends StatefulWidget {
  const ChordsScreen({
    super.key,
    this.isActive = true,
    ChordDetectorBloc Function()? blocBuilder,
  }) : _blocBuilder = blocBuilder;

  /// Onglet Chords visible à l'écran (miroir BUG-03) — piloté par
  /// `MainShell`, branché dès la conception (cf. §3.7 de
  /// `docs/STRATEGIE_DETECTION_ACCORDS.md`).
  final bool isActive;
  final ChordDetectorBloc Function()? _blocBuilder;

  @override
  State<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends State<ChordsScreen> {
  late final ChordDetectorBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc =
        (widget._blocBuilder ??
        () => ChordDetectorBloc(
          ChordRepositoryImpl(RecordMicrophoneDataSource()),
        ))();
    if (widget.isActive) _bloc.add(const StartChordDetection());
  }

  @override
  void didUpdateWidget(covariant ChordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _bloc.add(
        widget.isActive
            ? const StartChordDetection()
            : const StopChordDetection(),
      );
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: _bloc, child: const _ChordsView());
  }
}

class _ChordsView extends StatelessWidget {
  const _ChordsView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChordDetectorBloc, ChordDisplayState>(
      buildWhen: (prev, next) =>
          (prev is ChordPermissionDeniedState) !=
          (next is ChordPermissionDeniedState),
      builder: (context, state) {
        if (state is ChordPermissionDeniedState) {
          return _PermissionDeniedView(isPermanent: state.isPermanent);
        }
        return const _ChordsContent();
      },
    );
  }
}

// ── Vue de refus de permission (miroir Tuner, Scénario A1) ───────────────────

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
            const Icon(
              Icons.mic_off_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const Gap(24),
            Text(
              'Accès au microphone requis',
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(12),
            Text(
              'Le détecteur d\'accords a besoin du microphone pour '
              'reconnaître les accords joués sur votre instrument.',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
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
                onPressed: () => context.read<ChordDetectorBloc>().add(
                  const StartChordDetection(),
                ),
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Réessayer'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Contenu principal du détecteur d'accords ──────────────────────────────────

class _ChordsContent extends StatelessWidget {
  const _ChordsContent();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const AppHeader(),
          const Spacer(),
          const ChordNameDisplay(),
          const Gap(40),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: ChromaBarWidget(),
          ),
          const Spacer(),
          const Gap(8),
        ],
      ),
    );
  }
}
