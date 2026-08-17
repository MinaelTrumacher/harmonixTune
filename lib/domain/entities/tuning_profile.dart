import '../enums/instrument_type.dart';

// Profil d'accordage persisté (créé par l'utilisateur ou fourni par défaut).
// Distinct de TuningConfiguration : cette dernière reste l'état d'exécution
// du tuner en temps réel (SRP — voir docs/UC_02_strategy.md §4.1).
class TuningProfile {
  const TuningProfile({
    required this.id,
    required this.name,
    required this.instrumentType,
    required this.stringNotes,
    this.isUserDefined = true,
  });

  final String id;
  final String name;
  final InstrumentType instrumentType;
  final List<String> stringNotes;
  final bool isUserDefined;

  TuningProfile copyWith({
    String? id,
    String? name,
    InstrumentType? instrumentType,
    List<String>? stringNotes,
    bool? isUserDefined,
  }) {
    return TuningProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      instrumentType: instrumentType ?? this.instrumentType,
      stringNotes: stringNotes ?? this.stringNotes,
      isUserDefined: isUserDefined ?? this.isUserDefined,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TuningProfile) return false;
    if (other.id != id) return false;
    if (other.name != name) return false;
    if (other.instrumentType != instrumentType) return false;
    if (other.isUserDefined != isUserDefined) return false;
    if (other.stringNotes.length != stringNotes.length) return false;
    for (int i = 0; i < stringNotes.length; i++) {
      if (other.stringNotes[i] != stringNotes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    instrumentType,
    isUserDefined,
    Object.hashAll(stringNotes),
  );
}
