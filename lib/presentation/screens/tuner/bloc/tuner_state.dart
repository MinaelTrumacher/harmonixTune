import 'package:equatable/equatable.dart';
import '../../../../domain/entities/pitch_result.dart';
import '../../../../domain/entities/tuning_configuration.dart';

sealed class TunerDisplayState extends Equatable {
  const TunerDisplayState();
  @override
  List<Object?> get props => [];
}

final class TunerInitial extends TunerDisplayState {
  const TunerInitial({this.config = const TuningConfiguration()});

  // Permet aux widgets pilotés par la config (sélecteur de cordes, de
  // preset) de refléter la config courante même avant toute détection de
  // hauteur — sans ce champ, un changement de preset appliqué avant que le
  // micro n'ait capté un premier son restait invisible à l'écran (la config
  // interne du BLoC était pourtant à jour).
  final TuningConfiguration config;

  @override
  List<Object?> get props => [config];
}

final class TunerListening extends TunerDisplayState {
  const TunerListening({
    required this.pitch,
    required this.config,
    required this.intelliTunerEnabled,
  });

  final PitchResult pitch;
  final TuningConfiguration config;
  final bool intelliTunerEnabled;

  @override
  List<Object?> get props => [pitch, config, intelliTunerEnabled];
}

final class TunerPermissionDeniedState extends TunerDisplayState {
  const TunerPermissionDeniedState({required this.isPermanent});

  final bool isPermanent;

  @override
  List<Object?> get props => [isPermanent];
}
