import '../enums/tuner_state.dart';

class PitchResult {
  const PitchResult({
    required this.frequencyHz,
    required this.noteName,
    required this.octave,
    required this.centsDeviation,
    required this.confidence,
    required this.state,
  });

  final double frequencyHz;
  final String noteName;
  final int octave;
  final double centsDeviation;
  final double confidence;
  final TunerState state;

  static const PitchResult silent = PitchResult(
    frequencyHz: 0,
    noteName: '--',
    octave: 0,
    centsDeviation: 0,
    confidence: 0,
    state: TunerState.silent,
  );

  PitchResult copyWith({
    double? frequencyHz,
    String? noteName,
    int? octave,
    double? centsDeviation,
    double? confidence,
    TunerState? state,
  }) {
    return PitchResult(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      noteName: noteName ?? this.noteName,
      octave: octave ?? this.octave,
      centsDeviation: centsDeviation ?? this.centsDeviation,
      confidence: confidence ?? this.confidence,
      state: state ?? this.state,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PitchResult &&
        other.noteName == noteName &&
        other.octave == octave &&
        other.state == state &&
        // Comparaison à la précision affichée (1 décimale) — deux résultats
        // dont les valeurs affichées sont identiques sont traités comme égaux,
        // ce qui permet à BlocBuilder de sauter les rebuilds inutiles.
        other.frequencyHz.toStringAsFixed(1) == frequencyHz.toStringAsFixed(1) &&
        other.centsDeviation.toStringAsFixed(1) == centsDeviation.toStringAsFixed(1) &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(
        noteName,
        octave,
        state,
        frequencyHz.toStringAsFixed(1),
        centsDeviation.toStringAsFixed(1),
        confidence,
      );
}
