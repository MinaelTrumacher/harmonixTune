import '../validators/tuning_profile_validation_issue.dart';

// Levée par TuningProfileValidator dès qu'une ou plusieurs règles métier
// sont violées. Toutes les violations sont collectées (pas de fail-fast) afin
// que l'IHM puisse afficher un retour visuel précis sur chaque corde en erreur.
class InvalidTuningProfileException implements Exception {
  const InvalidTuningProfileException(this.issues);

  final List<TuningProfileValidationIssue> issues;

  @override
  String toString() =>
      'InvalidTuningProfileException: ${issues.map((i) => i.message).join('; ')}';
}
