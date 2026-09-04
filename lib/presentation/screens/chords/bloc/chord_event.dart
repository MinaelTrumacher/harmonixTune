import 'package:equatable/equatable.dart';
import '../../../../domain/entities/chord_result.dart';

sealed class ChordEvent extends Equatable {
  const ChordEvent();
  @override
  List<Object?> get props => [];
}

final class StartChordDetection extends ChordEvent {
  const StartChordDetection();
}

final class StopChordDetection extends ChordEvent {
  const StopChordDetection();
}

final class ChordReceived extends ChordEvent {
  const ChordReceived(this.result);
  final ChordResult result;
  @override
  List<Object?> get props => [result];
}

final class ChordPermissionDenied extends ChordEvent {
  const ChordPermissionDenied({required this.isPermanent});
  final bool isPermanent;
  @override
  List<Object?> get props => [isPermanent];
}
