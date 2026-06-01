import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/data/datasources/microphone_data_source.dart';
import 'package:harmonix_tune/data/repositories/audio_repository_impl.dart';
import 'package:harmonix_tune/domain/entities/pitch_result.dart';
import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/exceptions/audio_permission_exception.dart';

class MockMicrophoneDataSource extends Mock implements MicrophoneDataSource {}

Uint8List buildPcmBuffer(double freqHz, {double amplitude = 0.8}) {
  const n = AudioConstants.bufferSize;
  const sr = AudioConstants.sampleRate;
  final bytes = ByteData(n * 2);
  for (int i = 0; i < n; i++) {
    final s = (amplitude * sin(2 * pi * freqHz * i / sr) * 32767)
        .round()
        .clamp(-32768, 32767);
    bytes.setInt16(i * 2, s, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  late MockMicrophoneDataSource mockSource;
  late AudioRepositoryImpl repo;

  setUp(() {
    mockSource = MockMicrophoneDataSource();
    when(() => mockSource.initialize()).thenAnswer((_) async {});
    when(() => mockSource.dispose()).thenAnswer((_) async {});
    when(() => mockSource.stream())
        .thenAnswer((_) => const Stream<Uint8List>.empty());
    repo = AudioRepositoryImpl(mockSource);
  });

  tearDown(() async {
    await repo.stop();
  });

  // ── streamPitch — contrat de base ─────────────────────────────────────────

  group('AudioRepositoryImpl — streamPitch', () {
    test('retourne un Stream non null sans souscrire (lazy : pas d\'isolate)', () {
      // _start() n'est PAS appelé avant un abonné → pas d'isolate → tearDown rapide
      final stream = repo.streamPitch(const TuningConfiguration());
      expect(stream, isA<Stream<PitchResult>>());
    });

    test('appelle initialize() après souscription', () async {
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(() => mockSource.initialize()).called(1);
      await sub.cancel();
    });

    test('appelle stream() après initialize() réussi', () async {
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      verify(() => mockSource.stream()).called(1);
      await sub.cancel();
    });

    test('produit un PitchResult à partir d\'un chunk PCM A4', () async {
      final pcmController = StreamController<Uint8List>();
      when(() => mockSource.stream())
          .thenAnswer((_) => pcmController.stream);

      final results = <PitchResult>[];
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen(results.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      pcmController.add(buildPcmBuffer(440.0));

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(results, isNotEmpty);
      expect(results.first.noteName, equals('A'));
      expect(results.first.octave, equals(4));

      await sub.cancel();
      await pcmController.close();
    });

    test('ne produit rien pour un chunk silencieux', () async {
      final pcmController = StreamController<Uint8List>();
      when(() => mockSource.stream())
          .thenAnswer((_) => pcmController.stream);

      final results = <PitchResult>[];
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen(results.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      pcmController.add(Uint8List(AudioConstants.bufferSize * 2));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(results, isEmpty);

      await sub.cancel();
      await pcmController.close();
    });
  });

  // ── permission refusée (Scénario A1) ─────────────────────────────────────

  group('AudioRepositoryImpl — permission refusée (A1)', () {
    test('propage AudioPermissionException dans le stream', () async {
      when(() => mockSource.initialize())
          .thenThrow(const AudioPermissionException());

      final errors = <Object>[];
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen((_) {}, onError: errors.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(errors, isNotEmpty);
      expect(errors.first, isA<AudioPermissionException>());

      await sub.cancel();
    });

    test('isPermanent=true quand refus définitif', () async {
      when(() => mockSource.initialize())
          .thenThrow(const AudioPermissionException(isPermanent: true));

      final errors = <Object>[];
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen((_) {}, onError: errors.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(errors.first, isA<AudioPermissionException>());
      expect((errors.first as AudioPermissionException).isPermanent, isTrue);

      await sub.cancel();
    });
  });

  // ── updateConfig ──────────────────────────────────────────────────────────

  group('AudioRepositoryImpl — updateConfig', () {
    test('updateConfig sans abonné actif ne lève pas d\'exception', () async {
      expect(
        () => repo.updateConfig(const TuningConfiguration()),
        returnsNormally,
      );
    });
  });

  // ── stop ──────────────────────────────────────────────────────────────────

  group('AudioRepositoryImpl — stop', () {
    test('stop() sans abonné ne lève pas d\'exception', () async {
      repo.streamPitch(const TuningConfiguration()); // crée le controller
      await expectLater(repo.stop(), completes);
    });

    test('stop() avec abonné appelle dispose() sur le DataSource', () async {
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await repo.stop();
      verify(() => mockSource.dispose()).called(1);
      // sub already cancelled by stop → safe to call cancel again
      await sub.cancel().catchError((_) {});
    });

    test('stop() idempotent — second appel sans exception', () async {
      repo.streamPitch(const TuningConfiguration());
      await repo.stop();
      await expectLater(repo.stop(), completes);
    });

    test('stream se ferme après stop()', () async {
      final pcmController = StreamController<Uint8List>();
      when(() => mockSource.stream())
          .thenAnswer((_) => pcmController.stream);

      bool done = false;
      final sub = repo
          .streamPitch(const TuningConfiguration())
          .listen((_) {}, onDone: () => done = true);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await repo.stop();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(done, isTrue);

      await sub.cancel().catchError((_) {});
      await pcmController.close();
    });
  });
}
