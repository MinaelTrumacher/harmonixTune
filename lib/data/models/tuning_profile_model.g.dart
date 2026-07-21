// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tuning_profile_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TuningProfileModelAdapter extends TypeAdapter<TuningProfileModel> {
  @override
  final int typeId = 0;

  @override
  TuningProfileModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TuningProfileModel(
      id: fields[0] as String,
      name: fields[1] as String,
      instrumentTypeName: fields[2] as String,
      stringNotes: (fields[3] as List).cast<String>(),
      isUserDefined: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, TuningProfileModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.instrumentTypeName)
      ..writeByte(3)
      ..write(obj.stringNotes)
      ..writeByte(4)
      ..write(obj.isUserDefined);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TuningProfileModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
