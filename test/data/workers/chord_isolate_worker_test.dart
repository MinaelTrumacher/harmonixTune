import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/data/workers/chord_isolate_worker.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Construit [hopCount] hops PCM 16-bit consécutifs à partir d'une somme de
/// sinusoïdes, en conservant une phase continue d'un hop à l'autre (sinon la
/// concaténation en fenêtre FFT introduirait une discontinuité artificielle
/// à la frontière des hops).
List<Uint8List> buildContinuousHops(
  List<double> freqsHz,
  int hopCount, {
  double amplitude = 0.3,
}) {
  const sampleRate = AudioConstants.sampleRate;
  final hopSize = AudioConstants.chordHopSize;
  final totalSamples = hopSize * hopCount;
  final bytes = ByteData(totalSamples * 2);
  for (int i = 0; i < totalSamples; i++) {
    double sample = 0.0;
    for (final f in freqsHz) {
      sample += amplitude * sin(2 * pi * f * i / sampleRate);
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

/// Spawn le worker et retourne son [SendPort] après le handshake initial.
Future<({SendPort workerPort, Stream<dynamic> responses})>
spawnChordWorker() async {
  final mainPort = ReceivePort();
  await Isolate.spawn(chordIsolateEntryPoint, mainPort.sendPort);
  final stream = mainPort.asBroadcastStream();
  final workerPort = await stream.first as SendPort;
  return (workerPort: workerPort, responses: stream);
}

void main() {
  group('computeRms', () {
    test('signal nul → 0.0', () {
      expect(computeRms(Float64List(8)), 0.0);
    });

    test('signal constant [1,1,1,1] → 1.0', () {
      expect(computeRms(Float64List.fromList([1, 1, 1, 1])), 1.0);
    });

    test('signal carré [-1,1,-1,1] → 1.0', () {
      expect(computeRms(Float64List.fromList([-1, 1, -1, 1])), 1.0);
    });

    test('amplitude constante 0.5 → 0.5', () {
      expect(computeRms(Float64List.fromList([0.5, 0.5])), closeTo(0.5, 1e-9));
    });
  });

  group('activeNoteIndices', () {
    test('vecteur nul → aucun indice actif', () {
      expect(activeNoteIndices(List<double>.filled(12, 0.0), 0.5), isEmpty);
    });

    test('retient les degrés ≥ seuil, exclut les autres', () {
      final chroma = List<double>.filled(12, 0.0);
      chroma[0] = 1.0;
      chroma[4] = 0.6;
      chroma[7] = 0.4;
      expect(activeNoteIndices(chroma, 0.5), {0, 4});
    });
  });

  group('ChordWindowAccumulator — recouvrement 50 %', () {
    test('1er push → null (phase de chauffe)', () {
      final acc = ChordWindowAccumulator(hopSize: 2);
      expect(acc.push(Float64List.fromList([1, 2])), isNull);
    });

    test('2e push → fenêtre = hop précédent + hop courant', () {
      final acc = ChordWindowAccumulator(hopSize: 2);
      acc.push(Float64List.fromList([1, 2]));
      final window = acc.push(Float64List.fromList([3, 4]));
      expect(window, [1, 2, 3, 4]);
    });

    test('3e push → la fenêtre glisse d\'un hop (recouvrement 50 %)', () {
      final acc = ChordWindowAccumulator(hopSize: 2);
      acc.push(Float64List.fromList([1, 2]));
      acc.push(Float64List.fromList([3, 4]));
      final window = acc.push(Float64List.fromList([5, 6]));
      expect(window, [3, 4, 5, 6]);
    });
  });

  group('ChordIsolateWorker — handshake', () {
    test('renvoie un SendPort après le spawn', () async {
      final mainPort = ReceivePort();
      await Isolate.spawn(chordIsolateEntryPoint, mainPort.sendPort);
      final first = await mainPort.first;
      expect(first, isA<SendPort>());
      mainPort.close();
    });
  });

  group('ChordIsolateWorker — pipeline', () {
    test(
      '1er hop (non silencieux) → aucun message (phase de chauffe)',
      () async {
        final (:workerPort, :responses) = await spawnChordWorker();
        final hops = buildContinuousHops([261.63, 329.63, 392.0], 1);
        workerPort.send(
          ChordAudioBufferMessage(TransferableTypedData.fromList([hops[0]])),
        );

        await expectLater(
          responses.first.timeout(const Duration(milliseconds: 500)),
          throwsA(isA<TimeoutException>()),
        );
        workerPort.send(const KillChordWorkerMessage());
      },
    );

    test('accord Do majeur (C4,E4,G4) sur 2 hops → "C" détecté', () async {
      final (:workerPort, :responses) = await spawnChordWorker();
      final hops = buildContinuousHops([261.63, 329.63, 392.0], 2);
      for (final hop in hops) {
        workerPort.send(
          ChordAudioBufferMessage(TransferableTypedData.fromList([hop])),
        );
      }

      final msg = await responses
          .where((m) => m is ChordDetectedMessage)
          .first
          .timeout(const Duration(seconds: 5));

      final result = (msg as ChordDetectedMessage).result;
      expect(result.chordName, 'C');
      expect(result.confidence, greaterThan(AudioConstants.chordMinConfidence));
      expect(result.activeNoteIndices, containsAll([0, 4, 7]));
      workerPort.send(const KillChordWorkerMessage());
    });

    test(
      'signal silencieux → ChordResult.silent immédiat, même sur le 1er hop',
      () async {
        final (:workerPort, :responses) = await spawnChordWorker();
        workerPort.send(
          ChordAudioBufferMessage(
            TransferableTypedData.fromList([
              Uint8List(AudioConstants.chordHopSize * 2),
            ]),
          ),
        );

        final msg = await responses
            .where((m) => m is ChordDetectedMessage)
            .first
            .timeout(const Duration(seconds: 3));

        final result = (msg as ChordDetectedMessage).result;
        expect(result.chordName, '--');
        expect(result.confidence, 0.0);
        workerPort.send(const KillChordWorkerMessage());
      },
    );
  });
}
