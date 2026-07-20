enum TuningProfileValidationErrorType {
  invalidNameLength,
  duplicateName,
  invalidStringCount,
  invalidStringFormat,
  frequencyOutOfRange,
}

// Une violation d'une règle métier (voir TuningProfileValidator).
// `stringIndex` est renseigné uniquement pour les erreurs propres à une
// corde précise, afin que l'IHM puisse localiser l'erreur sur le bon champ.
class TuningProfileValidationIssue {
  const TuningProfileValidationIssue({
    required this.type,
    required this.message,
    this.stringIndex,
  });

  final TuningProfileValidationErrorType type;
  final String message;
  final int? stringIndex;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TuningProfileValidationIssue &&
        other.type == type &&
        other.message == message &&
        other.stringIndex == stringIndex;
  }

  @override
  int get hashCode => Object.hash(type, message, stringIndex);

  @override
  String toString() =>
      'TuningProfileValidationIssue(type: $type, stringIndex: $stringIndex, message: $message)';
}
