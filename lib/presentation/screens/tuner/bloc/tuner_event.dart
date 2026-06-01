import 'package:equatable/equatable.dart';
import '../../../../domain/entities/tuning_configuration.dart';

sealed class TunerEvent extends Equatable {
  const TunerEvent();
  @override
  List<Object?> get props => [];
}

final class StartTuner extends TunerEvent {
  const StartTuner();
}

final class StopTuner extends TunerEvent {
  const StopTuner();
}

final class PitchReceived extends TunerEvent {
  const PitchReceived(this.frequencyHz, this.centsDeviation);
  final double frequencyHz;
  final double centsDeviation;
  @override
  List<Object?> get props => [frequencyHz, centsDeviation];
}

final class ConfigChanged extends TunerEvent {
  const ConfigChanged(this.config);
  final TuningConfiguration config;
  @override
  List<Object?> get props => [config];
}

final class StringSelected extends TunerEvent {
  const StringSelected(this.stringNote);
  final String? stringNote; // null = mode AUTO
  @override
  List<Object?> get props => [stringNote];
}

final class IntelliTunerToggled extends TunerEvent {
  const IntelliTunerToggled({required this.enabled});
  final bool enabled;
  @override
  List<Object?> get props => [enabled];
}

final class DebugCentsOverride extends TunerEvent {
  const DebugCentsOverride(this.cents);
  final double cents;
  @override
  List<Object?> get props => [cents];
}
