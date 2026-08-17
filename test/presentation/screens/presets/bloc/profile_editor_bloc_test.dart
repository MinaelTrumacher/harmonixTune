import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';
import 'package:harmonix_tune/domain/repositories/tuning_profile_repository.dart';
import 'package:harmonix_tune/domain/validators/tuning_profile_validation_issue.dart';
import 'package:harmonix_tune/presentation/screens/presets/bloc/profile_editor_bloc.dart';
import 'package:harmonix_tune/presentation/screens/presets/bloc/profile_editor_event.dart';
import 'package:harmonix_tune/presentation/screens/presets/bloc/profile_editor_state.dart';

class MockTuningProfileRepository extends Mock
    implements TuningProfileRepository {}

class FakeTuningProfile extends Fake implements TuningProfile {}

const _fixedId = 'fixed-test-id';

void main() {
  setUpAll(() {
    registerFallbackValue(FakeTuningProfile());
  });

  late MockTuningProfileRepository mockRepo;

  setUp(() {
    mockRepo = MockTuningProfileRepository();
    when(() => mockRepo.watchAll()).thenAnswer((_) => Stream.value(const []));
    when(() => mockRepo.save(any())).thenAnswer((_) async {});
  });

  ProfileEditorBloc makeBloc() => ProfileEditorBloc(mockRepo);

  group('ProfileEditorBloc — état initial', () {
    test('brouillon initial : guitare, 6 cordes standard, nom vide', () {
      final bloc = makeBloc();
      expect(bloc.state, isA<ProfileEditorEditing>());
      expect(bloc.state.draft.instrumentType, InstrumentType.guitar);
      expect(bloc.state.draft.stringNotes, hasLength(6));
      expect(bloc.state.draft.name, isEmpty);
      expect(bloc.state.issues, isEmpty);
      bloc.close();
    });
  });

  group('ProfileNameChanged', () {
    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'met à jour le nom du brouillon',
      build: makeBloc,
      act: (b) => b.add(const ProfileNameChanged('Open G Keith Richards')),
      expect: () => [
        isA<ProfileEditorEditing>().having(
          (s) => s.draft.name,
          'name',
          'Open G Keith Richards',
        ),
      ],
    );
  });

  group('ProfileInstrumentTypeChanged', () {
    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'change le gabarit de cordes en changeant d\'instrument (ukulélé = 4 cordes)',
      build: makeBloc,
      act: (b) =>
          b.add(const ProfileInstrumentTypeChanged(InstrumentType.ukulele)),
      expect: () => [
        isA<ProfileEditorEditing>()
            .having(
              (s) => s.draft.instrumentType,
              'instrumentType',
              InstrumentType.ukulele,
            )
            .having((s) => s.draft.stringNotes, 'stringNotes', hasLength(4)),
      ],
    );
  });

  group('StringNoteChanged', () {
    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'modifie la note d\'une corde précise',
      build: makeBloc,
      act: (b) => b.add(const StringNoteChanged(index: 0, note: 'D2')),
      expect: () => [
        isA<ProfileEditorEditing>().having(
          (s) => s.draft.stringNotes[0],
          'corde 0',
          'D2',
        ),
      ],
    );

    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'index hors bornes ignoré (aucune émission)',
      build: makeBloc,
      act: (b) => b.add(const StringNoteChanged(index: 99, note: 'D2')),
      expect: () => <ProfileEditorState>[],
    );
  });

  group('StringAdded / StringRemoved', () {
    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'StringAdded ajoute une corde (6 → 7)',
      build: makeBloc,
      act: (b) => b.add(const StringAdded()),
      expect: () => [
        isA<ProfileEditorEditing>().having(
          (s) => s.draft.stringNotes,
          'stringNotes',
          hasLength(7),
        ),
      ],
    );

    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'StringAdded refuse au-delà de 8 cordes',
      build: makeBloc,
      seed: () => ProfileEditorEditing(
        draft: const TuningProfile(
          id: _fixedId,
          name: '',
          instrumentType: InstrumentType.custom,
          stringNotes: ['E1', 'A1', 'D2', 'G2', 'C3', 'F3', 'A3', 'D4'],
        ),
      ),
      act: (b) => b.add(const StringAdded()),
      expect: () => <ProfileEditorState>[],
    );

    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'StringRemoved retire une corde (6 → 5)',
      build: makeBloc,
      act: (b) => b.add(const StringRemoved(0)),
      expect: () => [
        isA<ProfileEditorEditing>().having(
          (s) => s.draft.stringNotes,
          'stringNotes',
          hasLength(5),
        ),
      ],
    );

    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'StringRemoved refuse sous 3 cordes',
      build: makeBloc,
      seed: () => ProfileEditorEditing(
        draft: const TuningProfile(
          id: _fixedId,
          name: '',
          instrumentType: InstrumentType.custom,
          stringNotes: ['E2', 'A2', 'D3'],
        ),
      ),
      act: (b) => b.add(const StringRemoved(0)),
      expect: () => <ProfileEditorState>[],
    );
  });

  group('SaveProfile — succès', () {
    // Open G (D-G-D-G-B-D) partage 2 notes avec le gabarito standard (D3, B3)
    // à ces positions — ces 2 events ne changent donc pas le brouillon et ne
    // produisent pas de nouvelle émission (Bloc ne réémet pas un état ==
    // à l'état courant, cf. PitchResult.== dans le tuner). D'où `skip: 4`
    // plutôt qu'un décompte figé des états intermédiaires.
    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'profil valide : sauvegarde via le repository et émet ProfileEditorSaved',
      build: makeBloc,
      act: (b) {
        b.add(const ProfileNameChanged('Open G Keith Richards'));
        b.add(const StringNoteChanged(index: 0, note: 'D2'));
        b.add(const StringNoteChanged(index: 1, note: 'G2'));
        b.add(const StringNoteChanged(index: 2, note: 'D3'));
        b.add(const StringNoteChanged(index: 4, note: 'B3'));
        b.add(const StringNoteChanged(index: 5, note: 'D4'));
        b.add(const SaveProfile());
      },
      wait: const Duration(milliseconds: 50),
      skip: 4,
      expect: () => [isA<ProfileEditorSaved>()],
      verify: (_) {
        final captured = verify(() => mockRepo.save(captureAny())).captured;
        expect(captured, hasLength(1));
        final saved = captured.single as TuningProfile;
        expect(saved.name, 'Open G Keith Richards');
        expect(saved.stringNotes, ['D2', 'G2', 'D3', 'G3', 'B3', 'D4']);
      },
    );
  });

  group('SaveProfile — validation refusée', () {
    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'nom vide : reste en édition avec les issues, ne sauvegarde pas',
      build: makeBloc,
      act: (b) => b.add(const SaveProfile()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<ProfileEditorEditing>().having(
          (s) => s.issues,
          'issues',
          isNotEmpty,
        ),
      ],
      verify: (_) => verifyNever(() => mockRepo.save(any())),
    );

    blocTest<ProfileEditorBloc, ProfileEditorState>(
      'nom déjà utilisé par un autre profil : duplicateName rapporté',
      build: () {
        when(() => mockRepo.watchAll()).thenAnswer(
          (_) => Stream.value([
            const TuningProfile(
              id: 'other-id',
              name: 'Open G Keith Richards',
              instrumentType: InstrumentType.guitar,
              stringNotes: ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
            ),
          ]),
        );
        return makeBloc();
      },
      act: (b) {
        b.add(const ProfileNameChanged('Open G Keith Richards'));
        b.add(const SaveProfile());
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<ProfileEditorEditing>(),
        isA<ProfileEditorEditing>().having(
          (s) => s.issues,
          'issues',
          contains(
            predicate<TuningProfileValidationIssue>(
              (i) => i.type == TuningProfileValidationErrorType.duplicateName,
            ),
          ),
        ),
      ],
      verify: (_) => verifyNever(() => mockRepo.save(any())),
    );
  });
}
