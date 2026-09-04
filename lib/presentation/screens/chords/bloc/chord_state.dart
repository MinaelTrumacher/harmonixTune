import 'package:equatable/equatable.dart';
import 'chord_smoother.dart';

sealed class ChordDisplayState extends Equatable {
  const ChordDisplayState();
  @override
  List<Object?> get props => [];
}

final class ChordInitial extends ChordDisplayState {
  const ChordInitial();
}

final class ChordListening extends ChordDisplayState {
  const ChordListening({required this.smoothed});

  final SmoothedChord smoothed;

  @override
  List<Object?> get props => [smoothed];
}

final class ChordPermissionDeniedState extends ChordDisplayState {
  const ChordPermissionDeniedState({required this.isPermanent});

  final bool isPermanent;

  @override
  List<Object?> get props => [isPermanent];
}
