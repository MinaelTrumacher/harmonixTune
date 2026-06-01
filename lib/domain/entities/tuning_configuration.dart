import '../enums/sweetening_strategy.dart';
import '../enums/instrument_type.dart';

class TuningConfiguration {
  const TuningConfiguration({
    this.referencePitchHz = 440.0,
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

  TuningConfiguration copyWith({
    double? referencePitchHz,
    SweeteningStrategy? sweetening,
    List<String>? stringNotes,
    Object? targetString = _sentinel,
    InstrumentType? instrumentType,
  }) {
    return TuningConfiguration(
      referencePitchHz: referencePitchHz ?? this.referencePitchHz,
      sweetening: sweetening ?? this.sweetening,
      stringNotes: stringNotes ?? this.stringNotes,
      targetString: targetString == _sentinel
          ? this.targetString
          : targetString as String?,
      instrumentType: instrumentType ?? this.instrumentType,
    );
  }
}

// Sentinel pour distinguer null explicite de "non fourni" dans copyWith
const Object _sentinel = Object();
