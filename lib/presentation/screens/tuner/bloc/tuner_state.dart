import 'package:equatable/equatable.dart';
import '../../../../domain/entities/pitch_result.dart';
import '../../../../domain/entities/tuning_configuration.dart';

sealed class TunerDisplayState extends Equatable {
  const TunerDisplayState();
  @override
  List<Object?> get props => [];
}

final class TunerInitial extends TunerDisplayState {
  const TunerInitial();
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
