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
  });

  final double referencePitchHz;
  final SweeteningStrategy sweetening;
  final List<String> stringNotes;
  final String? targetString;
  final InstrumentType instrumentType;

  static const TuningConfiguration standard = TuningConfiguration();

  // clearTargetString = true → remet targetString à null (mode AUTO)
  // Remplace le pattern sentinel Object? pour éviter le cast non sécurisé.
  TuningConfiguration copyWith({
    double? referencePitchHz,
    SweeteningStrategy? sweetening,
    List<String>? stringNotes,
    String? targetString,
    bool clearTargetString = false,
    InstrumentType? instrumentType,
  }) {
    return TuningConfiguration(
      referencePitchHz: referencePitchHz ?? this.referencePitchHz,
      sweetening: sweetening ?? this.sweetening,
      stringNotes: stringNotes ?? this.stringNotes,
      targetString:
          clearTargetString ? null : (targetString ?? this.targetString),
      instrumentType: instrumentType ?? this.instrumentType,
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
        Object.hashAll(stringNotes),
      );
}
