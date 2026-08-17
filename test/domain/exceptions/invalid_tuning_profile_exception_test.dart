import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/exceptions/invalid_tuning_profile_exception.dart';
import 'package:harmonix_tune/domain/validators/tuning_profile_validation_issue.dart';

void main() {
  group('InvalidTuningProfileException', () {
    test('expose la liste des issues fournies', () {
      const issues = [
        TuningProfileValidationIssue(
          type: TuningProfileValidationErrorType.invalidNameLength,
          message: 'nom invalide',
        ),
      ];
      const e = InvalidTuningProfileException(issues);
      expect(e.issues, equals(issues));
    });

    test('toString concatène les messages de chaque issue', () {
      const e = InvalidTuningProfileException([
        TuningProfileValidationIssue(
          type: TuningProfileValidationErrorType.invalidStringCount,
          message: 'trop peu de cordes',
        ),
        TuningProfileValidationIssue(
          type: TuningProfileValidationErrorType.duplicateName,
          message: 'nom déjà utilisé',
        ),
      ]);
      expect(e.toString(), contains('trop peu de cordes'));
      expect(e.toString(), contains('nom déjà utilisé'));
    });

    test('est une Exception', () {
      expect(const InvalidTuningProfileException([]), isA<Exception>());
    });
  });

  group('TuningProfileValidationIssue — égalité', () {
    test('deux issues aux mêmes champs sont égales', () {
      const a = TuningProfileValidationIssue(
        type: TuningProfileValidationErrorType.frequencyOutOfRange,
        message: 'msg',
        stringIndex: 2,
      );
      const b = TuningProfileValidationIssue(
        type: TuningProfileValidationErrorType.frequencyOutOfRange,
        message: 'msg',
        stringIndex: 2,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('stringIndex différent brise l\'égalité', () {
      const a = TuningProfileValidationIssue(
        type: TuningProfileValidationErrorType.frequencyOutOfRange,
        message: 'msg',
        stringIndex: 0,
      );
      const b = TuningProfileValidationIssue(
        type: TuningProfileValidationErrorType.frequencyOutOfRange,
        message: 'msg',
        stringIndex: 1,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
