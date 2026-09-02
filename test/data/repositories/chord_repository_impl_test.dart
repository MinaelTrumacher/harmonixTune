import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/data/datasources/microphone_data_source.dart';
import 'package:harmonix_tune/data/repositories/chord_repository_impl.dart';
import 'package:harmonix_tune/domain/entities/chord_result.dart';
import 'package:harmonix_tune/domain/exceptions/audio_permission_exception.dart';

class MockMicrophoneDataSource extends Mock implements MicrophoneDataSource {}

/// 2 hops PCM consécutifs (accord Do majeur), à phase continue — nécessaire
/// pour que le recouvrement 50 % de `ChordWindowAccumulator` produise une
/// fenêtre exploitable dès le 2e hop (cf. chord_isolate_worker_test.dart).
List<Uint8List> buildChordPcmHops(List<double> freqsHz, int hopCount) {
  const sampleRate = AudioConstants.sampleRate;
  final hopSize = AudioConstants.chordHopSize;
  final totalSamples = hopSize * hopCount;
  final bytes = ByteData(totalSamples * 2);
  for (int i = 0; i < totalSamples; i++) {
    double sample = 0.0;
    for (final f in freqsHz) {
      sample += 0.3 * sin(2 * pi * f * i / sampleRate);
    }
    final clamped = (sample * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(i * 2, clamped, Endian.little);
  }
  final all = bytes.buffer.asUint8List();
  return [
    for (int h = 0; h < hopCount; h++)
      all.sublist(h * hopSize * 2, (h + 1) * hopSize * 2),
  ];
}

void main() {
  late MockMicrophoneDataSource mockSource;
  late ChordRepositoryImpl repo;

  setUp(() {
    mockSource = MockMicrophoneDataSource();
    when(() => mockSource.initialize()).thenAnswer((_) async {});
    when(() => mockSource.dispose()).thenAnswer((_) async {});
    when(
      () => mockSource.stream(),
    ).thenAnswer((_) => const Stream<Uint8List>.empty());
    repo = ChordRepositoryImpl(mockSource);
  });

  tearDown(() async {
    await repo.stop();
  });

  // ── streamChord — contrat de base ─────────────────────────────────────────

  group('ChordRepositoryImpl — streamChord', () {
    test(
      'retourne un Stream non null sans souscrire (lazy : pas d\'isolate)',
      () {
        final stream = repo.streamChord();
        expect(stream, isA<Stream<ChordResult>>());
      },
    );

    test('appelle initialize() après souscription', () async {
      final sub = repo.streamChord().listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(() => mockSource.initialize()).called(1);
      await sub.cancel();
    });

    test('appelle stream() après initialize() réussi', () async {
      final sub = repo.streamChord().listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      verify(() => mockSource.stream()).called(1);
      await sub.cancel();
    });

    test(
      'produit un ChordResult "C" à partir de 2 chunks PCM (Do majeur)',
      () async {
        final pcmController = StreamController<Uint8List>();
        when(() => mockSource.stream()).thenAnswer((_) => pcmController.stream);

        final results = <ChordResult>[];
        final sub = repo.streamChord().listen(results.add);

        await Future<void>.delayed(const Duration(milliseconds: 200));
        for (final hop in buildChordPcmHops([261.63, 329.63, 392.0], 2)) {
          pcmController.add(hop);
        }

        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(results, isNotEmpty);
        expect(results.last.chordName, equals('C'));

        await sub.cancel();
        await pcmController.close();
      },
    );

    test('produit un ChordResult.silent pour un chunk silencieux', () async {
      final pcmController = StreamController<Uint8List>();
      when(() => mockSource.stream()).thenAnswer((_) => pcmController.stream);

      final results = <ChordResult>[];
      final sub = repo.streamChord().listen(results.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      pcmController.add(Uint8List(AudioConstants.chordHopSize * 2));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(results, isNotEmpty);
      expect(results.first.chordName, equals('--'));
      expect(results.first.confidence, equals(0.0));

      await sub.cancel();
      await pcmController.close();
    });
  });

  // ── permission refusée (Scénario A1, mirroir du Tuner) ────────────────────

  group('ChordRepositoryImpl — permission refusée', () {
    test('propage AudioPermissionException dans le stream', () async {
      when(
        () => mockSource.initialize(),
      ).thenThrow(const AudioPermissionException());

      final errors = <Object>[];
      final sub = repo.streamChord().listen((_) {}, onError: errors.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(errors, isNotEmpty);
      expect(errors.first, isA<AudioPermissionException>());

      await sub.cancel();
    });

    test('isPermanent=true quand refus définitif', () async {
      when(
        () => mockSource.initialize(),
      ).thenThrow(const AudioPermissionException(isPermanent: true));

      final errors = <Object>[];
      final sub = repo.streamChord().listen((_) {}, onError: errors.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(errors.first, isA<AudioPermissionException>());
      expect((errors.first as AudioPermissionException).isPermanent, isTrue);

      await sub.cancel();
    });
  });

  // ── stop ──────────────────────────────────────────────────────────────────

  group('ChordRepositoryImpl — stop', () {
    test('stop() sans abonné ne lève pas d\'exception', () async {
      repo.streamChord(); // crée le controller
      await expectLater(repo.stop(), completes);
    });

    test('stop() avec abonné appelle dispose() sur le DataSource', () async {
      final sub = repo.streamChord().listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await repo.stop();
      verify(() => mockSource.dispose()).called(1);
      await sub.cancel().catchError((_) {});
    });

    test('stop() idempotent — second appel sans exception', () async {
      repo.streamChord();
      await repo.stop();
      await expectLater(repo.stop(), completes);
    });

    test('stream se ferme après stop()', () async {
      final pcmController = StreamController<Uint8List>();
      when(() => mockSource.stream()).thenAnswer((_) => pcmController.stream);

      bool done = false;
      final sub = repo.streamChord().listen((_) {}, onDone: () => done = true);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await repo.stop();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(done, isTrue);

      await sub.cancel().catchError((_) {});
      await pcmController.close();
    });
  });
}
