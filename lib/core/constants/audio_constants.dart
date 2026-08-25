abstract final class AudioConstants {
  static const int sampleRate = 44100;
  static const int bufferSize = 2048;
  static const double inTuneThresholdCents = 2.0;
  static const double nearTuneThresholdCents = 5.0;
  static const double minConfidence = 0.85;
  static const double referenceA4Hz = 440.0;

  // Fréquences théoriques des cordes (accord standard, A4 = 440 Hz).
  // Utilisées par l'Isolate worker pour centrer le filtre IIR.
  // Limite basse : E2 = 82.41 Hz → τ ≈ 535, dans la plage τ_max = N/2 = 1024.
  static const Map<String, double> stringFrequencies = {
    'E2': 82.41,
    'A2': 110.00,
    'D3': 146.83,
    'G3': 196.00,
    'B3': 246.94,
    'E4': 329.63,
  };

  // minDetectableHz = sampleRate / (bufferSize / 2) ≈ 43 Hz.
  // En dessous de cette limite, τ dépasse N/2 et l'algorithme YIN ne peut
  // pas fonctionner avec un buffer de 2048 samples.
  static const double minDetectableHz = sampleRate / (bufferSize / 2);

  // ── Détection d'accords (US3) — cf. docs/STRATEGIE_DETECTION_ACCORDS.md ──

  // Taille FFT (résolution) et hop (cadence de rafraîchissement). hopSize
  // == bufferSize : le flux micro livre déjà des chunks de cette taille,
  // donc l'Isolate accords obtient un recouvrement de 50 % en concaténant
  // 2 hops consécutifs, sans toucher à RecordMicrophoneDataSource.
  static const int chordFftSize = 4096;
  static const int chordHopSize = bufferSize;

  static const double chordSilenceRmsThreshold = 0.01;
  static const double chordMinFreqHz = 70.0;
  static const double chordMaxFreqHz = 3000.0;

  // Score de similitude cosinus en dessous duquel un accord n'est pas
  // considéré comme fiable. Calibré juste sous 2/3 ≈ 0,667, le score
  // structurel entre un accord et son relatif majeur/mineur (ex. C/Am) —
  // cf. chord_template_library_test.dart.
  static const double chordMinConfidence = 0.65;

  // Fraction du degré chromatique dominant (vecteur normalisé [0,1]) à
  // partir de laquelle un degré est considéré comme une note active.
  static const double chordActiveNoteThreshold = 0.5;

  // Lissage anti-scintillement (ChordSmoother, couche Présentation).
  static const int chordSmootherWindowCount = 3;
  static const int chordHoldFramesOnIndetermination = 2;
}
