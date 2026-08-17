import 'package:equatable/equatable.dart';

import '../../../../domain/enums/instrument_type.dart';

sealed class ProfileEditorEvent extends Equatable {
  const ProfileEditorEvent();
  @override
  List<Object?> get props => [];
}

final class ProfileNameChanged extends ProfileEditorEvent {
  const ProfileNameChanged(this.name);
  final String name;
  @override
  List<Object?> get props => [name];
}

final class ProfileInstrumentTypeChanged extends ProfileEditorEvent {
  const ProfileInstrumentTypeChanged(this.instrumentType);
  final InstrumentType instrumentType;
  @override
  List<Object?> get props => [instrumentType];
}

final class StringNoteChanged extends ProfileEditorEvent {
  const StringNoteChanged({required this.index, required this.note});
  final int index;
  final String note;
  @override
  List<Object?> get props => [index, note];
}

final class StringAdded extends ProfileEditorEvent {
  const StringAdded();
}

final class StringRemoved extends ProfileEditorEvent {
  const StringRemoved(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

final class SaveProfile extends ProfileEditorEvent {
  const SaveProfile();
}
