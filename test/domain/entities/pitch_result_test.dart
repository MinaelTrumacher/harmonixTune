import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/entities/pitch_result.dart';
import 'package:harmonix_tune/domain/enums/tuner_state.dart';

PitchResult base() => const PitchResult(
      frequencyHz: 440.0,
      noteName: 'A',
      octave: 4,
      centsDeviation: 0.0,
      confidence: 0.95,
      state: TunerState.inTune,
    );

void main() {
  group('PitchResult — constructeur & constante', () {
    test('PitchResult.silent a les bonnes valeurs', () {
      expect(PitchResult.silent.frequencyHz, 0);
      expect(PitchResult.silent.noteName, '--');
      expect(PitchResult.silent.state, TunerState.silent);
      expect(PitchResult.silent.confidence, 0);
    });
  });

  group('PitchResult — copyWith', () {
    test('copie sans argument retourne un objet égal', () {
      final copy = base().copyWith();
      expect(copy, equals(base()));
    });

    test('copie en changeant frequencyHz', () {
      final copy = base().copyWith(frequencyHz: 880.0);
      expect(copy.frequencyHz, 880.0);
      expect(copy.noteName, 'A');
    });

    test('copie en changeant noteName', () {
      final copy = base().copyWith(noteName: 'E');
      expect(copy.noteName, 'E');
      expect(copy.frequencyHz, 440.0);
    });

    test('copie en changeant octave', () {
      expect(base().copyWith(octave: 3).octave, 3);
    });

    test('copie en changeant centsDeviation', () {
      expect(base().copyWith(centsDeviation: -10.5).centsDeviation, -10.5);
    });

    test('copie en changeant confidence', () {
      expect(base().copyWith(confidence: 0.5).confidence, 0.5);
    });

    test('copie en changeant state', () {
      expect(base().copyWith(state: TunerState.tooLow).state, TunerState.tooLow);
    });
  });

  group('PitchResult — égalité (==)', () {
    test('deux instances identiques sont égales', () {
      expect(base(), equals(base()));
    });

    test('différences de note brisent l\'égalité', () {
      expect(base(), isNot(equals(base().copyWith(noteName: 'B'))));
    });

    test('différences d\'octave brisent l\'égalité', () {
      expect(base(), isNot(equals(base().copyWith(octave: 3))));
    });

    test('différences de state brisent l\'égalité', () {
      expect(base(), isNot(equals(base().copyWith(state: TunerState.tooHigh))));
    });

    test('fréquences identiques à 1 décimale sont égales', () {
      final a = base().copyWith(frequencyHz: 440.01);
      final b = base().copyWith(frequencyHz: 440.04);
      expect(a, equals(b)); // 440.0 == 440.0 à 1 décimale
    });

    test('même objet est égal à lui-même (identical)', () {
      final r = base();
      expect(r, equals(r));
    });

    test('PitchResult != object d\'un autre type', () {
      // ignore: unrelated_type_equality_checks
      expect(base() == 'string', isFalse);
    });
  });

  group('PitchResult — hashCode', () {
    test('deux objets égaux ont le même hashCode', () {
      expect(base().hashCode, equals(base().hashCode));
    });

    test('hashCode diffère pour des notes différentes', () {
      expect(
        base().hashCode,
        isNot(equals(base().copyWith(noteName: 'E').hashCode)),
      );
    });
  });
}
