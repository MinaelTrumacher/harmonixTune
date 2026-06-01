import '../../core/constants/audio_constants.dart';
import '../enums/sweetening_strategy.dart';
import '../enums/instrument_type.dart';

class TuningConfiguration {
  const TuningConfiguration({
    this.referencePitchHz = AudioConstants.referenceA4Hz,
    this.sweetening = SweeteningStrategy.none,
    this.stringNotes = const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    this.targetString,
    this.instrumentType = InstrumentType.guitar,
    this.intelliTunerActive = false,
  });

  final double referencePitchHz;
  final SweeteningStrategy sweetening;
  final List<String> stringNotes;
  final String? targetString;
  final InstrumentType instrumentType;
  // Indique au worker d'activer le filtre IIR sur la fréquence de targetString.
  final bool intelliTunerActive;

  static const TuningConfiguration standard = TuningConfiguration();

  TuningConfiguration copyWith({
    double? referencePitchHz,
    SweeteningStrategy? sweetening,
    List<String>? stringNotes,
    String? targetString,
    bool clearTargetString = false,
    InstrumentType? instrumentType,
    bool? intelliTunerActive,
  }) {
    return TuningConfiguration(
      referencePitchHz: referencePitchHz ?? this.referencePitchHz,
      sweetening: sweetening ?? this.sweetening,
      stringNotes: stringNotes ?? this.stringNotes,
      targetString:
          clearTargetString ? null : (targetString ?? this.targetString),
      instrumentType: instrumentType ?? this.instrumentType,
      intelliTunerActive: intelliTunerActive ?? this.intelliTunerActive,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TuningConfiguration) return false;
    if (other.referencePitchHz != referencePitchHz) return false;
    if (other.sweetening != sweetening) return false;
    if (other.targetString != targetString) return false;
    if (other.instrumentType != instrumentType) return false;
    if (other.intelliTunerActive != intelliTunerActive) return false;
    if (other.stringNotes.length != stringNotes.length) return false;
    for (int i = 0; i < stringNotes.length; i++) {
      if (other.stringNotes[i] != stringNotes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        referencePitchHz,
        sweetening,
        targetString,
        instrumentType,
        intelliTunerActive,
        Object.hashAll(stringNotes),
      );
}
