import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/repositories/audio_repository.dart';
import 'package:harmonix_tune/domain/repositories/tuning_profile_repository.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_bloc.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_event.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_state.dart';
import 'package:harmonix_tune/presentation/screens/tuner/tuner_screen.dart';

class MockAudioRepository extends Mock implements AudioRepository {}

class MockTuningProfileRepository extends Mock
    implements TuningProfileRepository {}

class FakeTuningConfiguration extends Fake implements TuningConfiguration {}

class MockTunerBloc extends MockBloc<TunerEvent, TunerDisplayState>
    implements TunerBloc {}

// Le contenu réel de TunerScreen (header + toggle + cadran + slider debug)
// dépasse la taille de surface par défaut du test (800×600) → overflow de
// rendu sans rapport avec BUG-03 (cf. STRATEGIE_CORRECTION_BOGUES.md §3).
// On agrandit la surface et on consomme l'exception de layout associée
// pour ne tester que le câblage isActive → Start/Stop, pas le rendu.
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeTuningConfiguration());
    registerFallbackValue(const StartTuner());
  });

  // ── Montage initial : bloc réel + AudioRepository fake ──────────────────
  // Un seul cycle pompe/attente ici, sans transition supplémentaire — fiable
  // sans avoir besoin de faire avancer manuellement le pipeline d'événements
  // du bloc (cf. groupe ci-dessous pour les transitions rapprochées).

  group('montage initial (TunerBloc réel)', () {
    late MockAudioRepository mockRepo;
    late MockTuningProfileRepository mockProfileRepo;

    setUp(() {
      mockRepo = MockAudioRepository();
      when(() => mockRepo.stop()).thenAnswer((_) async {});
      when(() => mockRepo.updateConfig(any())).thenAnswer((_) async {});
      when(
        () => mockRepo.streamPitch(any()),
      ).thenAnswer((_) => const Stream.empty());

      mockProfileRepo = MockTuningProfileRepository();
      when(
        () => mockProfileRepo.watchAll(),
      ).thenAnswer((_) => Stream.value(const []));
    });

    Widget buildApp({required bool isActive}) {
      return MaterialApp(
        home: TunerScreen(
          isActive: isActive,
          tuningProfileRepository: mockProfileRepo,
          blocBuilder: () => TunerBloc(mockRepo),
        ),
      );
    }

    testWidgets('démarre l\'écoute au montage si isActive=true', (
      tester,
    ) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: true));
      tester
          .takeException(); // overflow de rendu, sans rapport (cf. note ci-dessus)
      await tester.pump(const Duration(milliseconds: 20));

      verify(() => mockRepo.streamPitch(any())).called(1);
    });

    testWidgets('ne démarre pas l\'écoute au montage si isActive=false', (
      tester,
    ) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: false));
      tester.takeException();
      await tester.pump(const Duration(milliseconds: 20));

      verifyNever(() => mockRepo.streamPitch(any()));
    });
  });

  // ── Transitions isActive : bloc mocké ────────────────────────────────────
  // On vérifie ici uniquement le câblage TunerScreen → bloc.add(...) sur
  // changement d'onglet, indépendamment du traitement interne des
  // événements par TunerBloc (déjà couvert par tuner_bloc_test.dart —
  // groupe "didChangeAppLifecycleState", test de sérialisation
  // Start/Stop). Évite de dépendre du pompage du pipeline de streams d'un
  // vrai bloc à travers plusieurs pumpWidget().

  group('transitions isActive (TunerBloc mocké)', () {
    late MockTunerBloc mockBloc;
    late MockTuningProfileRepository mockProfileRepo;

    setUp(() {
      mockBloc = MockTunerBloc();
      when(() => mockBloc.state).thenReturn(const TunerInitial());
      when(() => mockBloc.close()).thenAnswer((_) async {});

      mockProfileRepo = MockTuningProfileRepository();
      when(
        () => mockProfileRepo.watchAll(),
      ).thenAnswer((_) => Stream.value(const []));
    });

    Widget buildApp({required bool isActive}) {
      return MaterialApp(
        home: TunerScreen(
          isActive: isActive,
          tuningProfileRepository: mockProfileRepo,
          blocBuilder: () => mockBloc,
        ),
      );
    }

    testWidgets('coupe l\'écoute quand l\'onglet Tuner devient inactif', (
      tester,
    ) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: true));
      tester.takeException();

      await tester.pumpWidget(buildApp(isActive: false));

      verify(() => mockBloc.add(const StopTuner())).called(1);
    });

    testWidgets('sérialise Start/Stop sans les entrelacer sur un changement '
        'd\'onglet rapide (A→B→A)', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(buildApp(isActive: true));
      tester.takeException();

      await tester.pumpWidget(buildApp(isActive: false));
      await tester.pumpWidget(buildApp(isActive: true));

      verifyInOrder([
        () => mockBloc.add(const StartTuner()),
        () => mockBloc.add(const StopTuner()),
        () => mockBloc.add(const StartTuner()),
      ]);
    });
  });
}
