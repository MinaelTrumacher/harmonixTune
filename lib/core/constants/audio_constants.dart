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
}
