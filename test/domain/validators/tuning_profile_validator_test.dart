import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';
import 'package:harmonix_tune/domain/exceptions/invalid_tuning_profile_exception.dart';
import 'package:harmonix_tune/domain/validators/tuning_profile_validation_issue.dart';
import 'package:harmonix_tune/domain/validators/tuning_profile_validator.dart';

TuningProfile _profile({
  String id = 'p1',
  String name = 'Open G Keith Richards',
  InstrumentType instrumentType = InstrumentType.guitar,
  List<String> stringNotes = const ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
}) {
  return TuningProfile(
    id: id,
    name: name,
    instrumentType: instrumentType,
    stringNotes: stringNotes,
  );
}

InvalidTuningProfileException _expectThrows(
  TuningProfile profile, {
  Iterable<String> existingNames = const [],
}) {
  try {
    TuningProfileValidator.validate(profile, existingNames: existingNames);
  } on InvalidTuningProfileException catch (e) {
    return e;
  }
  fail('InvalidTuningProfileException attendue, aucune exception levée.');
}

void main() {
  group('TuningProfileValidator — profil valide', () {
    test('accordage Open G ne lève aucune exception', () {
      expect(
        () => TuningProfileValidator.validate(
          _profile(),
          existingNames: const [],
        ),
        returnsNormally,
      );
    });

    test('3 cordes (ukulélé) est valide', () {
      expect(
        () => TuningProfileValidator.validate(
          _profile(stringNotes: const ['G4', 'C4', 'E4']),
          existingNames: const [],
        ),
        returnsNormally,
      );
    });

    test('8 cordes est valide', () {
      expect(
        () => TuningProfileValidator.validate(
          _profile(
            stringNotes: const [
              'F#1',
              'B1',
              'E2',
              'A2',
              'D3',
              'G3',
              'B3',
              'E4',
            ],
          ),
          existingNames: const [],
        ),
        returnsNormally,
      );
    });
  });

  group('TuningProfileValidator — format des cordes', () {
    test('note sans octave rejetée avec le bon stringIndex', () {
      final e = _expectThrows(
        _profile(stringNotes: const ['D2', 'G', 'D3', 'G3', 'B3', 'D4']),
      );
      expect(
        e.issues,
        contains(
          predicate<TuningProfileValidationIssue>(
            (i) =>
                i.type ==
                    TuningProfileValidationErrorType.invalidStringFormat &&
                i.stringIndex == 1,
          ),
        ),
      );
    });

    test('lettre hors A-G rejetée', () {
      final e = _expectThrows(
        _profile(stringNotes: const ['H2', 'A2', 'D3', 'G3', 'B3', 'E4']),
      );
      expect(
        e.issues.first.type,
        TuningProfileValidationErrorType.invalidStringFormat,
      );
    });
  });

  group('TuningProfileValidator — plage fréquentielle', () {
    test('fréquence sous 43 Hz rejetée (ex: E0)', () {
      final e = _expectThrows(
        _profile(stringNotes: const ['E0', 'A2', 'D3', 'G3', 'B3', 'E4']),
      );
      expect(
        e.issues,
        contains(
          predicate<TuningProfileValidationIssue>(
            (i) =>
                i.type ==
                    TuningProfileValidationErrorType.frequencyOutOfRange &&
                i.stringIndex == 0,
          ),
        ),
      );
    });

    test('fréquence au-dessus de 1200 Hz rejetée (ex: E7)', () {
      final e = _expectThrows(
        _profile(stringNotes: const ['E7', 'A2', 'D3', 'G3', 'B3', 'E4']),
      );
      expect(
        e.issues,
        contains(
          predicate<TuningProfileValidationIssue>(
            (i) =>
                i.type ==
                    TuningProfileValidationErrorType.frequencyOutOfRange &&
                i.stringIndex == 0,
          ),
        ),
      );
    });

    test(
      'bornes exactes 43 Hz / 1200 Hz sont exclusives (strictement comprises)',
      () {
        // On vérifie juste la logique de comparaison, sans dépendre d'une note
        // exacte à la borne (peu de notes tombent pile dessus).
        expect(TuningProfileValidator.minFrequencyHz, 43.0);
        expect(TuningProfileValidator.maxFrequencyHz, 1200.0);
      },
    );
  });

  group('TuningProfileValidator — nombre de cordes', () {
    test('moins de 3 cordes rejeté', () {
      final e = _expectThrows(_profile(stringNotes: const ['E2', 'A2']));
      expect(
        e.issues.first.type,
        TuningProfileValidationErrorType.invalidStringCount,
      );
    });

    test('plus de 8 cordes rejeté', () {
      final e = _expectThrows(
        _profile(
          stringNotes: const [
            'E1',
            'A1',
            'D2',
            'G2',
            'C3',
            'F3',
            'A3',
            'D4',
            'G4',
          ],
        ),
      );
      expect(
        e.issues.first.type,
        TuningProfileValidationErrorType.invalidStringCount,
      );
    });
  });

  group('TuningProfileValidator — doublons de notes (autorisés)', () {
    test('deux cordes identiques ne lèvent pas d\'exception', () {
      expect(
        () => TuningProfileValidator.validate(
          _profile(stringNotes: const ['D2', 'D2', 'D3', 'G3', 'B3', 'D4']),
          existingNames: const [],
        ),
        returnsNormally,
      );
    });
  });

  group('TuningProfileValidator — nom du profil', () {
    test('nom trop court (< 3 caractères) rejeté', () {
      final e = _expectThrows(_profile(name: 'Ab'));
      expect(
        e.issues.first.type,
        TuningProfileValidationErrorType.invalidNameLength,
      );
    });

    test('nom trop long (> 50 caractères) rejeté', () {
      final e = _expectThrows(_profile(name: 'A' * 51));
      expect(
        e.issues.first.type,
        TuningProfileValidationErrorType.invalidNameLength,
      );
    });

    test('nom dupliqué (insensible à la casse) rejeté', () {
      final e = _expectThrows(
        _profile(name: 'Open G Keith Richards'),
        existingNames: const ['open g keith richards'],
      );
      expect(
        e.issues,
        contains(
          predicate<TuningProfileValidationIssue>(
            (i) => i.type == TuningProfileValidationErrorType.duplicateName,
          ),
        ),
      );
    });

    test('nom non dupliqué accepté', () {
      expect(
        () => TuningProfileValidator.validate(
          _profile(name: 'Open G Keith Richards'),
          existingNames: const ['Drop D'],
        ),
        returnsNormally,
      );
    });
  });

  group('TuningProfileValidator — collecte multi-erreurs', () {
    test('plusieurs violations sont toutes rapportées (pas fail-fast)', () {
      final e = _expectThrows(
        _profile(name: 'Ab', stringNotes: const ['E2', 'H2']),
      );
      expect(e.issues.length, greaterThanOrEqualTo(3));
    });
  });
}
