import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/data/workers/audio_isolate_worker.dart';
import 'package:harmonix_tune/domain/entities/pitch_result.dart';
import 'package:harmonix_tune/domain/entities/tuning_configuration.dart';
import 'package:harmonix_tune/domain/enums/tuner_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Construit un buffer PCM 16-bit (Uint8List) à partir d'une sinusoïde.
Uint8List buildPcmBuffer(double freqHz, {double amplitude = 0.8}) {
  const n = AudioConstants.bufferSize;
  const sr = AudioConstants.sampleRate;
  final bytes = ByteData(n * 2);
  for (int i = 0; i < n; i++) {
    final sample = (amplitude * sin(2 * pi * freqHz * i / sr) * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Spawn le worker et retourne son [SendPort] après le handshake initial.
Future<({SendPort workerPort, Stream<dynamic> responses})> spawnWorker([
  TuningConfiguration config = const TuningConfiguration(),
]) async {
  final mainPort = ReceivePort();
  await Isolate.spawn(audioIsolateEntryPoint, mainPort.sendPort);
  final stream = mainPort.asBroadcastStream();
  final workerPort = await stream.first as SendPort;
  // Envoyer la config initiale
  workerPort.send(InitWorkerMessage(config));
  return (workerPort: workerPort, responses: stream);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AudioIsolateWorker — handshake', () {
    test('renvoie un SendPort après le spawn', () async {
      final mainPort = ReceivePort();
      await Isolate.spawn(audioIsolateEntryPoint, mainPort.sendPort);
      final first = await mainPort.first;
      expect(first, isA<SendPort>());
      mainPort.close();
    });
  });

  group('AudioIsolateWorker — détection de pitch', () {
    test('retourne un PitchResult pour A4 (440 Hz) avec confiance ≥ 0.85', () async {
      final (:workerPort, :responses) = await spawnWorker();

      final pcm = buildPcmBuffer(440.0);
      workerPort.send(AudioBufferMessage(TransferableTypedData.fromList([pcm])));

      final msg = await responses
          .where((m) => m is PitchDetectedMessage)
          .first
          .timeout(const Duration(seconds: 3));

      final result = (msg as PitchDetectedMessage).result;
      expect(result.confidence, greaterThanOrEqualTo(AudioConstants.minConfidence));
      expect(result.frequencyHz, closeTo(440.0, 5.0));
      expect(result.noteName, equals('A'));
      expect(result.octave, equals(4));
      workerPort.send(const KillWorkerMessage());
    });

    test('retourne un PitchResult avec state=inTune pour A4 exact', () async {
      final (:workerPort, :responses) = await spawnWorker();

      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(440.0)]),
      ));

      final msg = await responses
          .where((m) => m is PitchDetectedMessage)
          .first
          .timeout(const Duration(seconds: 3));

      final result = (msg as PitchDetectedMessage).result;
      expect(result.state, equals(TunerState.inTune));
      workerPort.send(const KillWorkerMessage());
    });

    test('détecte E2 (82.41 Hz — corde grave de guitare)', () async {
      final (:workerPort, :responses) = await spawnWorker();

      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(82.41)]),
      ));

      final msg = await responses
          .where((m) => m is PitchDetectedMessage)
          .first
          .timeout(const Duration(seconds: 3));

      final result = (msg as PitchDetectedMessage).result;
      expect(result.noteName, equals('E'));
      expect(result.octave, equals(2));
      workerPort.send(const KillWorkerMessage());
    });

    test('ne retourne aucun message pour un signal silencieux', () async {
      final (:workerPort, :responses) = await spawnWorker();

      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([Uint8List(AudioConstants.bufferSize * 2)]),
      ));

      // Pas de PitchDetectedMessage attendu dans 500 ms
      final messages = <dynamic>[];
      final sub = responses
          .where((m) => m is PitchDetectedMessage)
          .listen(messages.add);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      sub.cancel();

      expect(messages, isEmpty);
      workerPort.send(const KillWorkerMessage());
    });
  });

  group('AudioIsolateWorker — mise à jour de config', () {
    test('UpdateConfigMessage modifie la config sans relancer le worker', () async {
      final (:workerPort, :responses) = await spawnWorker();

      // Changer config → mode MANUEL + intelli-tuner actif sur E2.
      workerPort.send(UpdateConfigMessage(
        const TuningConfiguration(
          targetString: 'E2',
          intelliTunerActive: true,
        ),
      ));

      // Buffer 1 : chauffe le filtre IIR (τ_settling ≈ 682 samples pour E2 à Q=4).
      // Le filtre IIR démarre à z1=z2=0 ; sur le premier buffer 2048 samples,
      // le transitoire couvre la fenêtre d'intégration YIN (1024 samples),
      // ce qui peut faire chuter la confiance sous le seuil.
      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(82.41)]),
      ));
      // Buffer 2 : filtre en régime permanent → confiance ≥ minConfidence.
      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(82.41)]),
      ));

      final msg = await responses
          .where((m) => m is PitchDetectedMessage)
          .first
          .timeout(const Duration(seconds: 5));

      final result = (msg as PitchDetectedMessage).result;
      expect(result.frequencyHz, closeTo(82.41, 5.0));
      workerPort.send(const KillWorkerMessage());
    });
  });

  group('AudioIsolateWorker — conversions note', () {
    final testCases = <(double, String, int)>[
      (440.00, 'A', 4),   // A4
      (329.63, 'E', 4),   // E4
      (246.94, 'B', 3),   // B3
      (196.00, 'G', 3),   // G3
      (146.83, 'D', 3),   // D3
      (110.00, 'A', 2),   // A2
      (82.41,  'E', 2),   // E2
    ];

    for (final (freq, note, octave) in testCases) {
      test('$freq Hz → $note$octave', () async {
        final (:workerPort, :responses) = await spawnWorker();

        workerPort.send(AudioBufferMessage(
          TransferableTypedData.fromList([buildPcmBuffer(freq)]),
        ));

        final msg = await responses
            .where((m) => m is PitchDetectedMessage)
            .first
            .timeout(const Duration(seconds: 3));

        final result = (msg as PitchDetectedMessage).result;
        expect(result.noteName, equals(note), reason: '$freq Hz');
        expect(result.octave, equals(octave), reason: '$freq Hz');
        workerPort.send(const KillWorkerMessage());
      });
    }
  });

  group('AudioIsolateWorker — TunerState', () {
    test('centsDeviation ≤ ±2 → state = inTune', () async {
      final (:workerPort, :responses) = await spawnWorker();
      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(440.0)]),
      ));
      final msg = await responses.where((m) => m is PitchDetectedMessage).first
          .timeout(const Duration(seconds: 3));
      expect((msg as PitchDetectedMessage).result.state, TunerState.inTune);
      workerPort.send(const KillWorkerMessage());
    });

    test('fréquence trop basse → state = tooLow', () async {
      final (:workerPort, :responses) = await spawnWorker();
      // A4 - 20 cents ≈ 434.5 Hz
      final double lowFreq = 440.0 * pow(2.0, -20 / 1200.0);
      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(lowFreq)]),
      ));
      final msg = await responses.where((m) => m is PitchDetectedMessage).first
          .timeout(const Duration(seconds: 3));
      expect((msg as PitchDetectedMessage).result.state, TunerState.tooLow);
      workerPort.send(const KillWorkerMessage());
    });

    test('fréquence trop haute → state = tooHigh', () async {
      final (:workerPort, :responses) = await spawnWorker();
      // A4 + 20 cents ≈ 445.5 Hz
      final double highFreq = 440.0 * pow(2.0, 20 / 1200.0);
      workerPort.send(AudioBufferMessage(
        TransferableTypedData.fromList([buildPcmBuffer(highFreq)]),
      ));
      final msg = await responses.where((m) => m is PitchDetectedMessage).first
          .timeout(const Duration(seconds: 3));
      expect((msg as PitchDetectedMessage).result.state, TunerState.tooHigh);
      workerPort.send(const KillWorkerMessage());
    });
  });
}
