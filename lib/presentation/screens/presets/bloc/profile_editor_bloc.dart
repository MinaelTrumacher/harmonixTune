import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/entities/tuning_profile.dart';
import '../../../../domain/enums/instrument_type.dart';
import '../../../../domain/exceptions/invalid_tuning_profile_exception.dart';
import '../../../../domain/repositories/tuning_profile_repository.dart';
import '../../../../domain/validators/tuning_profile_validator.dart';
import 'profile_editor_event.dart';
import 'profile_editor_state.dart';

// Gabarits de cordes par défaut, par instrument — toutes les fréquences
// restent dans la plage détectable [43, 1200] Hz du TuningProfileValidator.
// Note : l'accordage standard basse (E1 = 41.2 Hz) est hors de cette plage
// (limitation documentée dans docs/UC_01_strategy.md §3.1) ; le gabarit basse
// ci-dessous est donc décalé d'une corde pour rester détectable.
const Map<InstrumentType, List<String>> _defaultStringNotes = {
  InstrumentType.guitar: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  InstrumentType.bass: ['A1', 'D2', 'G2', 'C3'],
  InstrumentType.ukulele: ['G4', 'C4', 'E4', 'A4'],
  InstrumentType.custom: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
};

class ProfileEditorBloc extends Bloc<ProfileEditorEvent, ProfileEditorState> {
  ProfileEditorBloc(this._repository, {Uuid uuid = const Uuid()})
    : _uuid = uuid,
      super(
        ProfileEditorEditing(
          draft: TuningProfile(
            id: uuid.v4(),
            name: '',
            instrumentType: InstrumentType.guitar,
            stringNotes: List<String>.from(
              _defaultStringNotes[InstrumentType.guitar]!,
            ),
          ),
        ),
      ) {
    on<ProfileNameChanged>(_onNameChanged);
    on<ProfileInstrumentTypeChanged>(_onInstrumentTypeChanged);
    on<StringNoteChanged>(_onStringNoteChanged);
    on<StringAdded>(_onStringAdded);
    on<StringRemoved>(_onStringRemoved);
    on<SaveProfile>(_onSaveProfile);
  }

  final TuningProfileRepository _repository;
  // ignore: unused_field — réservé pour une future régénération d'id (duplication de profil)
  final Uuid _uuid;

  void _onNameChanged(
    ProfileNameChanged event,
    Emitter<ProfileEditorState> emit,
  ) {
    emit(ProfileEditorEditing(draft: state.draft.copyWith(name: event.name)));
  }

  void _onInstrumentTypeChanged(
    ProfileInstrumentTypeChanged event,
    Emitter<ProfileEditorState> emit,
  ) {
    emit(
      ProfileEditorEditing(
        draft: state.draft.copyWith(
          instrumentType: event.instrumentType,
          stringNotes: List<String>.from(
            _defaultStringNotes[event.instrumentType]!,
          ),
        ),
      ),
    );
  }

  void _onStringNoteChanged(
    StringNoteChanged event,
    Emitter<ProfileEditorState> emit,
  ) {
    final notes = List<String>.from(state.draft.stringNotes);
    if (event.index < 0 || event.index >= notes.length) return;
    notes[event.index] = event.note;
    emit(ProfileEditorEditing(draft: state.draft.copyWith(stringNotes: notes)));
  }

  void _onStringAdded(StringAdded event, Emitter<ProfileEditorState> emit) {
    if (state.draft.stringNotes.length >=
        TuningProfileValidator.maxStringCount) {
      return;
    }
    final notes = List<String>.from(state.draft.stringNotes)..add('E2');
    emit(ProfileEditorEditing(draft: state.draft.copyWith(stringNotes: notes)));
  }

  void _onStringRemoved(StringRemoved event, Emitter<ProfileEditorState> emit) {
    if (state.draft.stringNotes.length <=
        TuningProfileValidator.minStringCount) {
      return;
    }
    if (event.index < 0 || event.index >= state.draft.stringNotes.length) {
      return;
    }
    final notes = List<String>.from(state.draft.stringNotes)
      ..removeAt(event.index);
    emit(ProfileEditorEditing(draft: state.draft.copyWith(stringNotes: notes)));
  }

  Future<void> _onSaveProfile(
    SaveProfile event,
    Emitter<ProfileEditorState> emit,
  ) async {
    final existingProfiles = await _repository.watchAll().first;
    final existingNames = existingProfiles
        .where((profile) => profile.id != state.draft.id)
        .map((profile) => profile.name);

    try {
      TuningProfileValidator.validate(
        state.draft,
        existingNames: existingNames,
      );
    } on InvalidTuningProfileException catch (e) {
      emit(ProfileEditorEditing(draft: state.draft, issues: e.issues));
      return;
    }

    await _repository.save(state.draft);
    emit(ProfileEditorSaved(draft: state.draft));
  }
}
