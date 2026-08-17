import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';

TuningProfile _openG() => const TuningProfile(
  id: 'p1',
  name: 'Open G Keith Richards',
  instrumentType: InstrumentType.guitar,
  stringNotes: ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
);

void main() {
  group('TuningProfile — constructeur', () {
    test('isUserDefined vaut true par défaut', () {
      expect(_openG().isUserDefined, isTrue);
    });
  });

  group('TuningProfile — copyWith', () {
    test('copie sans argument retourne un objet égal', () {
      final base = _openG();
      expect(base.copyWith(), equals(base));
    });

    test('copyWith name', () {
      expect(_openG().copyWith(name: 'Drop D').name, 'Drop D');
    });

    test('copyWith stringNotes', () {
      expect(
        _openG().copyWith(stringNotes: ['E2']).stringNotes,
        equals(['E2']),
      );
    });

    test('copyWith isUserDefined', () {
      expect(_openG().copyWith(isUserDefined: false).isUserDefined, isFalse);
    });
  });

  group('TuningProfile — égalité (==)', () {
    test('deux instances aux mêmes champs sont égales', () {
      expect(_openG(), equals(_openG()));
    });

    test('différence d\'id brise l\'égalité', () {
      expect(_openG(), isNot(equals(_openG().copyWith(id: 'p2'))));
    });

    test('différence de stringNotes brise l\'égalité', () {
      expect(
        _openG(),
        isNot(equals(_openG().copyWith(stringNotes: ['E2', 'A2']))),
      );
    });

    test('même objet est égal à lui-même', () {
      final p = _openG();
      expect(p, equals(p));
    });

    test('TuningProfile != autre type', () {
      // ignore: unrelated_type_equality_checks
      expect(_openG() == 42, isFalse);
    });
  });

  group('TuningProfile — hashCode', () {
    test('deux objets égaux ont le même hashCode', () {
      expect(_openG().hashCode, equals(_openG().hashCode));
    });

    test('hashCode diffère si name change', () {
      expect(
        _openG().hashCode,
        isNot(equals(_openG().copyWith(name: 'Drop D').hashCode)),
      );
    });
  });
}
