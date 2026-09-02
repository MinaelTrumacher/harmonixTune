import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/chord_result.dart';
import 'package:harmonix_tune/domain/exceptions/audio_permission_exception.dart';
import 'package:harmonix_tune/domain/repositories/chord_repository.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_detector_bloc.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_event.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_smoother.dart';
import 'package:harmonix_tune/presentation/screens/chords/bloc/chord_state.dart';

class MockChordRepository extends Mock implements ChordRepository {}

ChordResult makeChord({
  String chordName = 'C',
  double confidence = 0.9,
  String? familyName,
}) => ChordResult(
  chordName: chordName,
  familyName: familyName ?? chordName,
  chromaVector: const [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0],
  confidence: confidence,
  activeNoteIndices: const {0, 4, 7},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockChordRepository mockRepo;

  setUp(() {
    mockRepo = MockChordRepository();
    when(() => mockRepo.stop()).thenAnswer((_) async {});
    when(
      () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
    ).thenAnswer((_) => const Stream.empty());
  });

  ChordDetectorBloc makeBloc() => ChordDetectorBloc(mockRepo);

  // ── StartChordDetection ────────────────────────────────────────────────────

  group('StartChordDetection', () {
    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'souscrit au stream du repo',
      build: makeBloc,
      act: (b) => b.add(const StartChordDetection()),
      verify: (_) => verify(
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
      ).called(1),
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'émet ChordListening quand ChordResult reçu',
      build: () {
        when(
          () =>
              mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
        ).thenAnswer((_) => Stream.value(makeChord()));
        return makeBloc();
      },
      act: (b) async {
        b.add(const StartChordDetection());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [isA<ChordListening>()],
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'émet ChordPermissionDeniedState sur AudioPermissionException',
      build: () {
        when(
          () =>
              mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
        ).thenAnswer((_) => Stream.error(const AudioPermissionException()));
        return makeBloc();
      },
      act: (b) async {
        b.add(const StartChordDetection());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [isA<ChordPermissionDeniedState>()],
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'isPermanent transmis dans ChordPermissionDeniedState',
      build: () {
        when(
          () =>
              mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
        ).thenAnswer(
          (_) =>
              Stream.error(const AudioPermissionException(isPermanent: true)),
        );
        return makeBloc();
      },
      act: (b) async {
        b.add(const StartChordDetection());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        isA<ChordPermissionDeniedState>().having(
          (s) => s.isPermanent,
          'isPermanent',
          isTrue,
        ),
      ],
    );
  });

  // ── StopChordDetection ──────────────────────────────────────────────────────

  group('StopChordDetection', () {
    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'émet ChordInitial et appelle stop() sur le repo',
      build: makeBloc,
      act: (b) async {
        b.add(const StartChordDetection());
        b.add(const StopChordDetection());
      },
      expect: () => [isA<ChordInitial>()],
      verify: (_) =>
          verify(() => mockRepo.stop()).called(greaterThanOrEqualTo(1)),
    );
  });

  // ── Cycle de vie app (miroir BUG-02) ─────────────────────────────────────

  group('didChangeAppLifecycleState', () {
    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'reprend l\'écoute au resume si en écoute avant la pause',
      build: makeBloc,
      seed: () => ChordListening(
        smoothed: SmoothedChord(
          kind: SmoothedChordKind.detected,
          result: makeChord(),
        ),
      ),
      act: (b) async {
        b.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        b.didChangeAppLifecycleState(AppLifecycleState.resumed);
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(() => mockRepo.stop()).called(greaterThanOrEqualTo(1));
        verify(
          () =>
              mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
        ).called(1);
      },
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'ne relance pas si l\'arrêt était manuel avant la pause',
      build: makeBloc, // état initial ChordInitial (pas ChordListening)
      act: (b) async {
        b.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        b.didChangeAppLifecycleState(AppLifecycleState.resumed);
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) => verifyNever(
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
      ),
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'sérialise Start/Stop rapprochés sans les entrelacer (BUG-03)',
      build: makeBloc,
      act: (b) {
        // Enchaînement sans attendre entre les add() — simule un
        // changement d'onglet rapide.
        b.add(const StartChordDetection());
        b.add(const StopChordDetection());
        b.add(const StartChordDetection());
      },
      wait: const Duration(milliseconds: 50),
      verify: (_) => verifyInOrder([
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
        () => mockRepo.stop(),
        () => mockRepo.streamChord(referenceA4Hz: any(named: 'referenceA4Hz')),
      ]),
    );
  });

  // ── ChordReceived ────────────────────────────────────────────────────────

  group('ChordReceived', () {
    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'émet ChordListening pour le premier accord reçu',
      build: makeBloc,
      act: (b) => b.add(ChordReceived(makeChord(chordName: 'E'))),
      expect: () => [isA<ChordListening>()],
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'confirme l\'accord (kind=detected) à la 3e réception identique '
      '(ChordSmoother : 2 frames d\'attaque ignorées avant le 1er vote)',
      build: makeBloc,
      act: (b) {
        b.add(ChordReceived(makeChord(chordName: 'G'))); // attaque, ignorée
        b.add(ChordReceived(makeChord(chordName: 'G'))); // attaque, ignorée
        b.add(ChordReceived(makeChord(chordName: 'G'))); // 1er vote
      },
      expect: () => [
        isA<ChordListening>().having(
          (s) => s.smoothed.kind,
          'kind',
          SmoothedChordKind.indeterminate,
        ),
        isA<ChordListening>().having(
          (s) => s.smoothed.kind,
          'kind',
          SmoothedChordKind.indeterminate,
        ),
        isA<ChordListening>()
            .having((s) => s.smoothed.kind, 'kind', SmoothedChordKind.detected)
            .having((s) => s.smoothed.result.chordName, 'chordName', 'G'),
      ],
    );
  });

  // ── ChordPermissionDenied ───────────────────────────────────────────────────

  group('ChordPermissionDenied', () {
    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'émet ChordPermissionDeniedState(isPermanent: false)',
      build: makeBloc,
      act: (b) => b.add(const ChordPermissionDenied(isPermanent: false)),
      expect: () => [
        isA<ChordPermissionDeniedState>().having(
          (s) => s.isPermanent,
          'isPermanent',
          isFalse,
        ),
      ],
    );

    blocTest<ChordDetectorBloc, ChordDisplayState>(
      'émet ChordPermissionDeniedState(isPermanent: true)',
      build: makeBloc,
      act: (b) => b.add(const ChordPermissionDenied(isPermanent: true)),
      expect: () => [
        isA<ChordPermissionDeniedState>().having(
          (s) => s.isPermanent,
          'isPermanent',
          isTrue,
        ),
      ],
    );
  });
}
