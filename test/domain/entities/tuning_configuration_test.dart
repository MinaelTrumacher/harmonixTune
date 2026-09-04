import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';
import 'package:harmonix_tune/domain/enums/sweetening_strategy.dart';

void main() {
  group('TuningConfiguration — constructeur & constante', () {
    test('valeurs par défaut correctes', () {
      const c = TuningConfiguration();
      expect(c.referencePitchHz, AudioConstants.referenceA4Hz);
      expect(c.sweetening, SweeteningStrategy.none);
      expect(c.targetString, isNull);
      expect(c.intelliTunerActive, isFalse);
      expect(c.instrumentType, InstrumentType.guitar);
      expect(c.presetId, isNull);
    });

    test(
      'TuningConfiguration.standard est équivalent à const TuningConfiguration()',
      () {
        expect(
          TuningConfiguration.standard,
          equals(const TuningConfiguration()),
        );
      },
    );
  });

  group('TuningConfiguration — copyWith', () {
    const base = TuningConfiguration();

    test('copie sans argument retourne un objet égal', () {
      expect(base.copyWith(), equals(base));
    });

    test('copyWith referencePitchHz', () {
      expect(base.copyWith(referencePitchHz: 432.0).referencePitchHz, 432.0);
    });

    test('copyWith targetString', () {
      expect(base.copyWith(targetString: 'E2').targetString, 'E2');
    });

    test('clearTargetString remet targetString à null', () {
      final withTarget = base.copyWith(targetString: 'A2');
      expect(withTarget.copyWith(clearTargetString: true).targetString, isNull);
    });

    test('copyWith intelliTunerActive', () {
      expect(
        base.copyWith(intelliTunerActive: true).intelliTunerActive,
        isTrue,
      );
    });

    test('copyWith instrumentType', () {
      expect(
        base.copyWith(instrumentType: InstrumentType.bass).instrumentType,
        InstrumentType.bass,
      );
    });

    test('copyWith presetId', () {
      expect(base.copyWith(presetId: 'p1').presetId, 'p1');
    });

    test('clearPresetId remet presetId à null', () {
      final withPreset = base.copyWith(presetId: 'p1');
      expect(withPreset.copyWith(clearPresetId: true).presetId, isNull);
    });
  });

  group('TuningConfiguration — égalité (==)', () {
    const a = TuningConfiguration();
    const b = TuningConfiguration();

    test('deux instances identiques sont égales', () {
      expect(a, equals(b));
    });

    test('différence de referencePitchHz brise l\'égalité', () {
      expect(a, isNot(equals(a.copyWith(referencePitchHz: 432.0))));
    });

    test('différence de targetString brise l\'égalité', () {
      expect(a, isNot(equals(a.copyWith(targetString: 'E2'))));
    });

    test('différence d\'intelliTunerActive brise l\'égalité', () {
      expect(a, isNot(equals(a.copyWith(intelliTunerActive: true))));
    });

    test('différence de stringNotes brise l\'égalité', () {
      expect(a, isNot(equals(a.copyWith(stringNotes: ['E2', 'A2']))));
    });

    test('différence de presetId brise l\'égalité', () {
      expect(a, isNot(equals(a.copyWith(presetId: 'p1'))));
    });

    test('même objet est égal à lui-même', () {
      expect(a, equals(a));
    });

    test('TuningConfiguration != autre type', () {
      // ignore: unrelated_type_equality_checks
      expect(a == 42, isFalse);
    });
  });

  group('TuningConfiguration — hashCode', () {
    test('deux objets égaux ont le même hashCode', () {
      expect(
        const TuningConfiguration().hashCode,
        equals(const TuningConfiguration().hashCode),
      );
    });

    test('hashCode diffère si targetString change', () {
      expect(
        const TuningConfiguration().hashCode,
        isNot(equals(const TuningConfiguration(targetString: 'E2').hashCode)),
      );
    });
  });
}
