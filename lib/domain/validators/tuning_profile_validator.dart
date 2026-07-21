import '../../core/utils/note_frequency_converter.dart';
import '../entities/tuning_profile.dart';
import '../exceptions/invalid_tuning_profile_exception.dart';
import 'tuning_profile_validation_issue.dart';

// Règles métier de cohérence d'un profil d'accordage (docs/UC_02_strategy.md §3).
// Validation pure : aucune dépendance Flutter ni Data — testable isolément.
abstract final class TuningProfileValidator {
  static const int minStringCount = 3;
  static const int maxStringCount = 8;
  static const int minNameLength = 3;
  static const int maxNameLength = 50;

  // Bornes calquées sur les limites physiques de l'algorithme YIN
  // (buffer 2048 @ 44100 Hz — voir docs/UC_01_strategy.md §3.1).
  static const double minFrequencyHz = 43.0;
  static const double maxFrequencyHz = 1200.0;

  // Valide `profile` et lève InvalidTuningProfileException si une règle
  // métier est violée. `existingNames` sert à vérifier l'unicité du nom ;
  // en cas d'édition d'un profil existant, exclure son propre nom courant
  // de cette liste avant l'appel.
  static void validate(
    TuningProfile profile, {
    required Iterable<String> existingNames,
  }) {
    final issues = <TuningProfileValidationIssue>[];

    final trimmedName = profile.name.trim();
    if (trimmedName.length < minNameLength ||
        trimmedName.length > maxNameLength) {
      issues.add(
        TuningProfileValidationIssue(
          type: TuningProfileValidationErrorType.invalidNameLength,
          message:
              'Le nom du profil doit contenir entre $minNameLength et '
              '$maxNameLength caractères.',
        ),
      );
    }

    final isDuplicate = existingNames.any(
      (existing) => existing.trim().toLowerCase() == trimmedName.toLowerCase(),
    );
    if (isDuplicate) {
      issues.add(
        const TuningProfileValidationIssue(
          type: TuningProfileValidationErrorType.duplicateName,
          message: 'Ce nom de profil est déjà utilisé.',
        ),
      );
    }

    if (profile.stringNotes.length < minStringCount ||
        profile.stringNotes.length > maxStringCount) {
      issues.add(
        TuningProfileValidationIssue(
          type: TuningProfileValidationErrorType.invalidStringCount,
          message:
              'Le profil doit comporter entre $minStringCount et '
              '$maxStringCount cordes (actuellement '
              '${profile.stringNotes.length}).',
        ),
      );
    }

    for (var i = 0; i < profile.stringNotes.length; i++) {
      final note = profile.stringNotes[i];
      final frequencyHz = NoteFrequencyConverter.toFrequencyHz(note);

      if (frequencyHz == null) {
        issues.add(
          TuningProfileValidationIssue(
            type: TuningProfileValidationErrorType.invalidStringFormat,
            stringIndex: i,
            message:
                'La corde ${i + 1} ("$note") doit être une note avec octave '
                '(ex: "E2").',
          ),
        );
        continue;
      }

      if (frequencyHz < minFrequencyHz || frequencyHz > maxFrequencyHz) {
        issues.add(
          TuningProfileValidationIssue(
            type: TuningProfileValidationErrorType.frequencyOutOfRange,
            stringIndex: i,
            message:
                'La corde ${i + 1} ("$note", ${frequencyHz.toStringAsFixed(1)} '
                'Hz) est hors de la plage détectable '
                '[$minFrequencyHz, $maxFrequencyHz] Hz.',
          ),
        );
      }
    }

    if (issues.isNotEmpty) {
      throw InvalidTuningProfileException(issues);
    }
  }
}
