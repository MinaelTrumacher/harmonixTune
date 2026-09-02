import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/repositories/chord_repository.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_detector_bloc.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_event.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_state.dart';
import 'package:harmonix_tune/presentation/screens/chords/chords_screen.dart';

class MockChordRepository extends Mock implements ChordRepository {}

class MockChordDetectorBloc extends MockBloc<ChordEvent, ChordDisplayState>
    implements ChordDetectorBloc {}

// Cf. tuner_screen_test.dart : le contenu réel (header + affichage accord +
// barres chroma) dépasse la surface par défaut du test → overflow de rendu
// sans rapport avec le câblage isActive. On agrandit la surface et on
// consomme l'exception associée.
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUpAll(() {
    registerFallbackValue(const StartChordDetection());
  });

  // ── Montage initial : bloc réel + ChordRepository fake ──────────────────

  group('montage initial (ChordDetectorBloc réel)', () {
    late MockChordRepository mockRepo;

    setUp(() {
      mockRepo = MockChordRepository();
      when(() => mockRepo.stop()).thenAnswer((_) async {});
      when(
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
      ).thenAnswer((_) => const Stream.empty());
    });

    Widget buildApp({required bool isActive}) {
      return MaterialApp(
        home: ChordsScreen(
          isActive: isActive,
          blocBuilder: () => ChordDetectorBloc(mockRepo),
        ),
      );
    }

    testWidgets('démarre l\'écoute au montage si isActive=true', (
      tester,
    ) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: true));
      tester.takeException();
      await tester.pump(const Duration(milliseconds: 20));

      verify(
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
      ).called(1);
    });

    testWidgets('ne démarre pas l\'écoute au montage si isActive=false', (
      tester,
    ) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: false));
      tester.takeException();
      await tester.pump(const Duration(milliseconds: 20));

      verifyNever(
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
      );
    });
  });

  // ── Transitions isActive : bloc mocké ────────────────────────────────────

  group('transitions isActive (ChordDetectorBloc mocké)', () {
    late MockChordDetectorBloc mockBloc;

    setUp(() {
      mockBloc = MockChordDetectorBloc();
      when(() => mockBloc.state).thenReturn(const ChordInitial());
      when(() => mockBloc.close()).thenAnswer((_) async {});
    });

    Widget buildApp({required bool isActive}) {
      return MaterialApp(
        home: ChordsScreen(isActive: isActive, blocBuilder: () => mockBloc),
      );
    }

    testWidgets('coupe l\'écoute quand l\'onglet Chords devient inactif', (
      tester,
    ) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: true));
      tester.takeException();

      await tester.pumpWidget(buildApp(isActive: false));

      verify(() => mockBloc.add(const StopChordDetection())).called(1);
    });

    testWidgets('sérialise Start/Stop sans les entrelacer sur un changement '
        'd\'onglet rapide (A→B→A)', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: true));
      tester.takeException();

      await tester.pumpWidget(buildApp(isActive: false));
      await tester.pumpWidget(buildApp(isActive: true));

      verifyInOrder([
        () => mockBloc.add(const StartChordDetection()),
        () => mockBloc.add(const StopChordDetection()),
        () => mockBloc.add(const StartChordDetection()),
      ]);
    });
  });
}
