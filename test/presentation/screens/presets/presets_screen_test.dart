import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/tuning_profile.dart';
import 'package:harmonix_tune/domain/enums/instrument_type.dart';
import 'package:harmonix_tune/domain/repositories/tuning_profile_repository.dart';
import 'package:harmonix_tune/presentation/screens/presets/presets_screen.dart';

class MockTuningProfileRepository extends Mock
    implements TuningProfileRepository {}

class FakeTuningProfile extends Fake implements TuningProfile {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeTuningProfile());
  });

  late MockTuningProfileRepository mockRepo;

  setUp(() {
    mockRepo = MockTuningProfileRepository();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  group('PresetsScreen — état vide', () {
    testWidgets('affiche le message "Aucun profil" quand la liste est vide', (
      tester,
    ) async {
      when(
        () => mockRepo.watchAll(),
      ).thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(wrap(PresetsScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      expect(find.text('Aucun profil d\'accordage'), findsOneWidget);
      expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
    });
  });

  group('PresetsScreen — liste de profils', () {
    const profiles = [
      TuningProfile(
        id: 'p1',
        name: 'Standard',
        instrumentType: InstrumentType.guitar,
        stringNotes: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
      ),
      TuningProfile(
        id: 'p2',
        name: 'Drop D',
        instrumentType: InstrumentType.bass,
        stringNotes: ['A1', 'D2', 'G2', 'C3'],
      ),
    ];

    testWidgets('affiche une tuile par profil avec nom et cordes', (
      tester,
    ) async {
      when(
        () => mockRepo.watchAll(),
      ).thenAnswer((_) => Stream.value(profiles));

      await tester.pumpWidget(wrap(PresetsScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Drop D'), findsOneWidget);
      expect(find.textContaining('E2 - A2 - D3 - G3 - B3 - E4'), findsOneWidget);
      expect(find.text('Aucun profil d\'accordage'), findsNothing);
    });

    testWidgets('appuyer sur supprimer appelle repository.delete(id)', (
      tester,
    ) async {
      when(
        () => mockRepo.watchAll(),
      ).thenAnswer((_) => Stream.value(profiles));
      when(() => mockRepo.delete(any())).thenAnswer((_) async {});

      await tester.pumpWidget(wrap(PresetsScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      verify(() => mockRepo.delete('p1')).called(1);
    });
  });

  group('PresetsScreen — navigation', () {
    testWidgets('le bouton flottant ouvre ProfileEditorScreen', (
      tester,
    ) async {
      when(
        () => mockRepo.watchAll(),
      ).thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(wrap(PresetsScreen(repository: mockRepo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Créer un profil'), findsOneWidget);
    });
  });
}
