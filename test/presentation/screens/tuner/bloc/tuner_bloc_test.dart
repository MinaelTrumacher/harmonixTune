import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:harmonix_tune/domain/entities/pitch_result.dart';
import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/enums/tuner_state.dart';
import 'package:harmonix_tune/domain/exceptions/audio_permission_exception.dart';
import 'package:harmonix_tune/domain/repositories/audio_repository.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_bloc.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_event.dart';
import 'package:harmonix_tune/presentation/screens/tuner/bloc/tuner_state.dart';

class MockAudioRepository extends Mock implements AudioRepository {}

// Valeur de repli pour les matchers any() qui attendent TuningConfiguration
class FakeTuningConfiguration extends Fake implements TuningConfiguration {}

PitchResult makePitch({
  double hz = 440.0,
  String note = 'A',
  int octave = 4,
  double cents = 0.0,
  double confidence = 0.95,
  TunerState state = TunerState.inTune,
}) => PitchResult(
  frequencyHz: hz,
  noteName: note,
  octave: octave,
  centsDeviation: cents,
  confidence: confidence,
  state: state,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeTuningConfiguration());
  });

  late MockAudioRepository mockRepo;

  setUp(() {
    mockRepo = MockAudioRepository();
    when(() => mockRepo.stop()).thenAnswer((_) async {});
    when(() => mockRepo.updateConfig(any())).thenAnswer((_) async {});
    when(
      () => mockRepo.streamPitch(any()),
    ).thenAnswer((_) => const Stream.empty());
  });

  TunerBloc makeBloc() => TunerBloc(mockRepo);

  // ── StartTuner ────────────────────────────────────────────────────────────

  group('StartTuner', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'souscrit au stream du repo',
      build: makeBloc,
      act: (b) => b.add(const StartTuner()),
      verify: (_) => verify(() => mockRepo.streamPitch(any())).called(1),
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerListening quand PitchResult reçu',
      build: () {
        final pitch = makePitch();
        when(
          () => mockRepo.streamPitch(any()),
        ).thenAnswer((_) => Stream.value(pitch));
        return makeBloc();
      },
      act: (b) async {
        b.add(const StartTuner());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [isA<TunerListening>()],
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerPermissionDeniedState sur AudioPermissionException',
      build: () {
        when(
          () => mockRepo.streamPitch(any()),
        ).thenAnswer((_) => Stream.error(const AudioPermissionException()));
        return makeBloc();
      },
      act: (b) async {
        b.add(const StartTuner());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [isA<TunerPermissionDeniedState>()],
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'isPermanent transmis dans TunerPermissionDeniedState',
      build: () {
        when(() => mockRepo.streamPitch(any())).thenAnswer(
          (_) =>
              Stream.error(const AudioPermissionException(isPermanent: true)),
        );
        return makeBloc();
      },
      act: (b) async {
        b.add(const StartTuner());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => [
        isA<TunerPermissionDeniedState>().having(
          (s) => s.isPermanent,
          'isPermanent',
          isTrue,
        ),
      ],
    );
  });

  // ── StopTuner ─────────────────────────────────────────────────────────────

  group('StopTuner', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerInitial et appelle stop() sur le repo',
      build: makeBloc,
      act: (b) async {
        b.add(const StartTuner());
        b.add(const StopTuner());
      },
      expect: () => [isA<TunerInitial>()],
      verify: (_) =>
          verify(() => mockRepo.stop()).called(greaterThanOrEqualTo(1)),
    );
  });

  // ── PitchReceived ─────────────────────────────────────────────────────────

  group('PitchReceived', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerListening avec le PitchResult reçu',
      build: makeBloc,
      act: (b) => b.add(PitchReceived(makePitch(note: 'E', octave: 4))),
      expect: () => [
        isA<TunerListening>().having((s) => s.pitch.noteName, 'noteName', 'E'),
      ],
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'auto-activation Intelli-Tuner : mode MANUEL + confiance faible',
      build: makeBloc,
      act: (b) async {
        // StringSelected met à jour _config.targetString (non null → mode MANUEL)
        // même depuis TunerInitial (le emit est conditionnel, pas la mise à jour).
        b.add(const StringSelected('E2'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        b.add(PitchReceived(makePitch(confidence: 0.60)));
      },
      verify: (_) => verify(
        () => mockRepo.updateConfig(any()),
      ).called(greaterThanOrEqualTo(1)),
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'pas d\'auto-activation si mode AUTO (targetString null)',
      build: makeBloc,
      act: (b) => b.add(PitchReceived(makePitch(confidence: 0.60))),
      verify: (_) => verifyNever(() => mockRepo.updateConfig(any())),
    );
  });

  // ── PermissionDenied ──────────────────────────────────────────────────────

  group('PermissionDenied', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerPermissionDeniedState(isPermanent: false)',
      build: makeBloc,
      act: (b) => b.add(const PermissionDenied(isPermanent: false)),
      expect: () => [
        isA<TunerPermissionDeniedState>().having(
          (s) => s.isPermanent,
          'isPermanent',
          isFalse,
        ),
      ],
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerPermissionDeniedState(isPermanent: true)',
      build: makeBloc,
      act: (b) => b.add(const PermissionDenied(isPermanent: true)),
      expect: () => [
        isA<TunerPermissionDeniedState>().having(
          (s) => s.isPermanent,
          'isPermanent',
          isTrue,
        ),
      ],
    );
  });

  // ── StringSelected ────────────────────────────────────────────────────────

  group('StringSelected', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'met à jour targetString dans l\'état TunerListening',
      build: makeBloc,
      seed: () => TunerListening(
        pitch: makePitch(),
        config: const TuningConfiguration(),
        intelliTunerEnabled: false,
      ),
      act: (b) => b.add(const StringSelected('A2')),
      expect: () => [
        isA<TunerListening>().having(
          (s) => s.config.targetString,
          'targetString',
          'A2',
        ),
      ],
    );

    blocTest<TunerBloc, TunerDisplayState>(
      'StringSelected(null) repasse en mode AUTO',
      build: makeBloc,
      seed: () => TunerListening(
        pitch: makePitch(),
        config: const TuningConfiguration(targetString: 'A2'),
        intelliTunerEnabled: true,
      ),
      act: (b) => b.add(const StringSelected(null)),
      expect: () => [
        isA<TunerListening>().having(
          (s) => s.config.targetString,
          'targetString',
          isNull,
        ),
      ],
    );
  });

  // ── IntelliTunerToggled ───────────────────────────────────────────────────

  group('IntelliTunerToggled', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'active Intelli-Tuner et met à jour le repo',
      build: makeBloc,
      seed: () => TunerListening(
        pitch: makePitch(),
        config: const TuningConfiguration(),
        intelliTunerEnabled: false,
      ),
      act: (b) => b.add(const IntelliTunerToggled(enabled: true)),
      expect: () => [
        isA<TunerListening>().having(
          (s) => s.intelliTunerEnabled,
          'intelliTunerEnabled',
          isTrue,
        ),
      ],
      verify: (_) => verify(() => mockRepo.updateConfig(any())).called(1),
    );
  });

  // ── DebugCentsOverride ────────────────────────────────────────────────────

  group('DebugCentsOverride', () {
    blocTest<TunerBloc, TunerDisplayState>(
      'émet TunerListening avec la valeur de cents fixée',
      build: makeBloc,
      act: (b) => b.add(const DebugCentsOverride(20.0)),
      expect: () => [
        isA<TunerListening>().having(
          (s) => s.pitch.centsDeviation,
          'centsDeviation',
          20.0,
        ),
      ],
    );
  });
}
