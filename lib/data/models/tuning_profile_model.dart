import 'package:hive/hive.dart';

import '../../domain/entities/tuning_profile.dart';
import '../../domain/enums/instrument_type.dart';

part 'tuning_profile_model.g.dart';

// Modèle de persistance Hive. Isolé de l'entité Domaine (TuningProfile) par
// des mappers explicites (fromEntity/toEntity) pour que le Domaine ne
// connaisse jamais Hive — seule cette couche Data en dépend.
@HiveType(typeId: 0)
class TuningProfileModel extends HiveObject {
  TuningProfileModel({
    required this.id,
    required this.name,
    required this.instrumentTypeName,
    required this.stringNotes,
    required this.isUserDefined,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String instrumentTypeName;

  @HiveField(3)
  final List<String> stringNotes;

  @HiveField(4)
  final bool isUserDefined;

  factory TuningProfileModel.fromEntity(TuningProfile entity) {
    return TuningProfileModel(
      id: entity.id,
      name: entity.name,
      instrumentTypeName: entity.instrumentType.name,
      stringNotes: List<String>.from(entity.stringNotes),
      isUserDefined: entity.isUserDefined,
    );
  }

  TuningProfile toEntity() {
    return TuningProfile(
      id: id,
      name: name,
      instrumentType: InstrumentType.values.byName(instrumentTypeName),
      stringNotes: List<String>.from(stringNotes),
      isUserDefined: isUserDefined,
    );
  }
}
