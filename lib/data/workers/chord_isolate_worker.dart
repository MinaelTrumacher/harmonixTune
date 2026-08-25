import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../core/constants/audio_constants.dart';
import '../../domain/entities/chord_result.dart';
import 'chord_template_library.dart';
import 'chromagram_builder.dart';
import 'spectral_peak_extractor.dart';

// ── Messages envoyés AU worker ────────────────────────────────────────────────

class InitChordWorkerMessage {
  const InitChordWorkerMessage({
    this.referenceA4Hz = AudioConstants.referenceA4Hz,
  });
  final double referenceA4Hz;
}

class ChordAudioBufferMessage {
  const ChordAudioBufferMessage(this.data);
  final TransferableTypedData data;
}

class KillChordWorkerMessage {
  const KillChordWorkerMessage();
}

// ── Message envoyé PAR le worker ──────────────────────────────────────────────

class ChordDetectedMessage {
  const ChordDetectedMessage(this.result);
  final ChordResult result;
}

// ── Point d'entrée de l'Isolate (fonction top-level obligatoire) ──────────────

void chordIsolateEntryPoint(SendPort mainSendPort) {
  final workerPort = ReceivePort();
  // Handshake : envoie le SendPort du worker au thread principal.
  mainSendPort.send(workerPort.sendPort);

  final peakExtractor = SpectralPeakExtractor(
    sampleRate: AudioConstants.sampleRate,
    fftSize: AudioConstants.chordFftSize,
    minFreqHz: AudioConstants.chordMinFreqHz,
    maxFreqHz: AudioConstants.chordMaxFreqHz,
  );
  final accumulator = ChordWindowAccumulator(
    hopSize: AudioConstants.chordHopSize,
  );
  // Buffer réutilisable — évite les allocations par frame dans la boucle DSP.
  final hopSamples = Float64List(AudioConstants.chordHopSize);
  double referenceA4Hz = AudioConstants.referenceA4Hz;

  workerPort.listen((message) {
    if (message is InitChordWorkerMessage) {
      referenceA4Hz = message.referenceA4Hz;
    } else if (message is ChordAudioBufferMessage) {
      _processHop(
        message.data,
        hopSamples,
        accumulator,
        peakExtractor,
        referenceA4Hz,
        mainSendPort,
      );
    } else if (message is KillChordWorkerMessage) {
      workerPort.close();
    }
  });
}

// ── Fenêtrage 50 % de recouvrement ─────────────────────────────────────────────

/// Accumule des hops de taille fixe [hopSize] et produit une fenêtre FFT de
/// taille `2 × hopSize` par concaténation des 2 derniers hops reçus — un
/// recouvrement de 50 % obtenu sans modifier `RecordMicrophoneDataSource`
/// (cf. § 3.2 de `docs/STRATEGIE_DETECTION_ACCORDS.md`).
@visibleForTesting
class ChordWindowAccumulator {
  ChordWindowAccumulator({required this.hopSize})
    : _window = Float64List(hopSize * 2),
      _previousHop = Float64List(hopSize);

  final int hopSize;
  final Float64List _window;
  final Float64List _previousHop;
  bool _warmedUp = false;

  /// [hop] doit contenir exactement [hopSize] échantillons. Retourne la
  /// fenêtre concaténée une fois le buffer chaud, sinon `null` (premier hop
  /// reçu = phase de chauffe, pas encore assez de données).
  ///
  /// La fenêtre retournée est une vue interne réutilisée à chaque appel —
  /// l'appelant ne doit pas en conserver de référence au-delà de l'appel.
  Float64List? push(Float64List hop) {
    if (!_warmedUp) {
      _previousHop.setAll(0, hop);
      _warmedUp = true;
      return null;
    }
    _window.setRange(0, hopSize, _previousHop);
    _window.setRange(hopSize, hopSize * 2, hop);
    _previousHop.setAll(0, hop);
    return _window;
  }
}

// ── Fonctions privées top-level (accessibles depuis l'Isolate) ────────────────

/// RMS (Root Mean Square) d'un buffer d'échantillons normalisés [-1.0, 1.0].
@visibleForTesting
double computeRms(Float64List samples) {
  double sumSquares = 0.0;
  for (final s in samples) {
    sumSquares += s * s;
  }
  return sqrt(sumSquares / samples.length);
}

/// Indices (convention MIDI `C=0`) des degrés chromatiques considérés comme
/// des notes actives : au moins [threshold] fois l'intensité du degré
/// dominant du vecteur (normalisé [0.0, 1.0]).
@visibleForTesting
Set<int> activeNoteIndices(List<double> chroma, double threshold) {
  final indices = <int>{};
  for (int i = 0; i < chroma.length; i++) {
    if (chroma[i] >= threshold) indices.add(i);
  }
  return indices;
}

void _processHop(
  TransferableTypedData transferable,
  Float64List hopSamples,
  ChordWindowAccumulator accumulator,
  SpectralPeakExtractor peakExtractor,
  double referenceA4Hz,
  SendPort replyPort,
) {
  // Reinterpret cast mémoire instantané : Uint8List → Int16List → Float64List.
  final int16 = transferable.materialize().asInt16List();
  final len = hopSamples.length < int16.length
      ? hopSamples.length
      : int16.length;
  for (int i = 0; i < len; i++) {
    hopSamples[i] = int16[i] / 32768.0;
  }

  final rms = computeRms(hopSamples);
  // Toujours alimenter l'accumulateur, même en silence : sinon la fenêtre
  // se désynchronise du recouvrement 50 % dès que le son reprend.
  final window = accumulator.push(hopSamples);

  if (rms < AudioConstants.chordSilenceRmsThreshold) {
    replyPort.send(const ChordDetectedMessage(ChordResult.silent));
    return;
  }
  if (window == null) return; // buffer pas encore chaud (1er hop)

  final peaks = peakExtractor.extract(window);
  final chroma = ChromagramBuilder.build(peaks, referenceA4Hz: referenceA4Hz);
  final match = ChordTemplateLibrary.match(chroma);

  replyPort.send(
    ChordDetectedMessage(
      ChordResult(
        chordName: match.chordName,
        chromaVector: chroma,
        confidence: match.confidence,
        activeNoteIndices: activeNoteIndices(
          chroma,
          AudioConstants.chordActiveNoteThreshold,
        ),
      ),
    ),
  );
}
