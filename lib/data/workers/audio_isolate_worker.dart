import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../../core/constants/audio_constants.dart';
import '../../domain/entities/pitch_result.dart';
import '../../domain/entities/tuning_configuration.dart';
import '../../domain/enums/tuner_state.dart';
import 'iir_bandpass_filter.dart';
import 'yin_detector.dart';

// ── Messages envoyés AU worker ────────────────────────────────────────────────

class InitWorkerMessage {
  const InitWorkerMessage(this.config);
  final TuningConfiguration config;
}

class AudioBufferMessage {
  const AudioBufferMessage(this.data);
  final TransferableTypedData data;
}

class UpdateConfigMessage {
  const UpdateConfigMessage(this.config);
  final TuningConfiguration config;
}

class KillWorkerMessage {
  const KillWorkerMessage();
}

// ── Message envoyé PAR le worker ──────────────────────────────────────────────

class PitchDetectedMessage {
  const PitchDetectedMessage(this.result);
  final PitchResult result;
}

// ── Point d'entrée de l'Isolate (fonction top-level obligatoire) ──────────────

void audioIsolateEntryPoint(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  // Handshake : envoie le SendPort du worker au thread principal.
  mainSendPort.send(workerPort.sendPort);

  final detector = YinDetector(
    sampleRate: AudioConstants.sampleRate,
    bufferSize: AudioConstants.bufferSize,
  );
  // Buffer réutilisable — évite les allocations par frame dans la boucle DSP.
  final samples = Float64List(AudioConstants.bufferSize);
  TuningConfiguration config = const TuningConfiguration();
  IirBandpassFilter? filter;

  workerPort.listen((message) {
    if (message is InitWorkerMessage) {
      config = message.config;
      filter = _buildFilter(config);
    } else if (message is AudioBufferMessage) {
      _processBuffer(
        message.data,
        samples,
        detector,
        filter,
        config,
        mainSendPort,
      );
    } else if (message is UpdateConfigMessage) {
      config = message.config;
      filter = _buildFilter(config);
    } else if (message is KillWorkerMessage) {
      workerPort.close();
    }
  });
}

// ── Fonctions privées top-level (accessibles depuis l'Isolate) ────────────────

IirBandpassFilter? _buildFilter(TuningConfiguration config) {
  if (!config.intelliTunerActive || config.targetString == null) return null;
  final centerHz = AudioConstants.stringFrequencies[config.targetString];
  if (centerHz == null) return null;
  return IirBandpassFilter(
    centerHz: centerHz,
    sampleRate: AudioConstants.sampleRate,
  );
}

void _processBuffer(
  TransferableTypedData transferable,
  Float64List samples,
  YinDetector detector,
  IirBandpassFilter? filter,
  TuningConfiguration config,
  SendPort replyPort,
) {
  // Reinterpret cast mémoire instantané : Uint8List → Int16List → Float64List.
  final int16 = transferable.materialize().asInt16List();
  final len = samples.length < int16.length ? samples.length : int16.length;
  for (int i = 0; i < len; i++) {
    samples[i] = int16[i] / 32768.0;
  }

  // Intelli-Tuner : filtre IIR passe-bande si actif (mode MANUEL + toggle on).
  filter?.process(samples);

  final detected = detector.detect(samples);
  if (detected == null || detected.confidence < AudioConstants.minConfidence) {
    return;
  }

  final note = _noteFromHz(detected.f0Hz, config.referencePitchHz);
  final state = _stateFromCents(note.centsDeviation);

  replyPort.send(
    PitchDetectedMessage(
      PitchResult(
        frequencyHz: detected.f0Hz,
        noteName: note.noteName,
        octave: note.octave,
        centsDeviation: note.centsDeviation,
        confidence: detected.confidence,
        state: state,
      ),
    ),
  );
}

/// Convertit une fréquence en nom de note, octave et écart en cents.
/// Référence : A4 = [referenceHz] (440 Hz par défaut).
({String noteName, int octave, double centsDeviation}) _noteFromHz(
  double f0Hz,
  double referenceHz,
) {
  const noteNames = [
    'A',
    'A#',
    'B',
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
  ];
  final semitones = (12 * log(f0Hz / referenceHz) / log(2)).round();
  final fRef = referenceHz * pow(2.0, semitones / 12.0);
  final cents = 1200 * log(f0Hz / fRef) / log(2);
  // noteIndex : modulo robuste aux négatifs
  final noteIndex = ((semitones % 12) + 12) % 12;
  // Octave via MIDI : A4 = MIDI 69, octave = midiNote ~/ 12 - 1
  final midiNote = 69 + semitones;
  final octave = midiNote ~/ 12 - 1;
  return (
    noteName: noteNames[noteIndex],
    octave: octave,
    centsDeviation: cents,
  );
}

TunerState _stateFromCents(double cents) {
  if (cents.abs() <= AudioConstants.inTuneThresholdCents) {
    return TunerState.inTune;
  }
  if (cents.abs() <= AudioConstants.nearTuneThresholdCents) {
    return TunerState.nearTune;
  }
  return cents < 0 ? TunerState.tooLow : TunerState.tooHigh;
}
