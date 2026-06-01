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
  const PitchReceived(this.frequencyHz, this.centsDeviation, {this.confidence = 1.0});
  final double frequencyHz;
  final double centsDeviation;
  // Fiabilité de la détection [0.0–1.0]. En dessous de AudioConstants.minConfidence
  // l'émission est ignorée par le BLoC (Phase 9 : valeur réelle depuis l'Isolate).
  final double confidence;
  @override
  List<Object?> get props => [frequencyHz, centsDeviation, confidence];
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
