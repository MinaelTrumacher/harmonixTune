import 'dart:math';

import 'spectral_peak_extractor.dart';

/// Construit un chromagramme (vecteur d'intensité 12D, convention MIDI
/// `C=0` — cf. `NoteFrequencyConverter.chromaticScale`) à partir des pics
/// spectraux extraits par [SpectralPeakExtractor] (US3 — détection
/// d'accords).
///
/// Chaque pic est replié sur son degré chromatique indépendamment de
/// l'octave, et pondéré par une compression logarithmique de sa magnitude —
/// évite qu'une seule note jouée avec beaucoup d'attaque n'écrase la tierce
/// ou la quinte dans le vecteur résultant (l'énergie brute |X(f)|² amplifie
/// trop fortement l'attaque par rapport au sustain des autres notes).
abstract final class ChromagramBuilder {
  /// [referenceA4Hz] : fréquence de A4 utilisée pour l'attribution du degré
  /// chromatique (tempérament égal). [compressionGamma] : facteur de la
  /// compression log(1 + γ·magnitude) — cf. cadrage US3. Les deux sont
  /// passés explicitement par l'appelant (pas de valeur par défaut couplée
  /// à `AudioConstants` ici — cohérent avec `YinDetector`/`IirBandpassFilter`),
  /// pour rester testable avec des valeurs arbitraires indépendamment du
  /// réglage courant de l'application.
  static List<double> build(
    List<SpectralPeak> peaks, {
    required double referenceA4Hz,
    required double compressionGamma,
  }) {
    final chroma = List<double>.filled(12, 0.0);
    for (final peak in peaks) {
      if (peak.frequencyHz <= 0) continue;

      // Degré chromatique : A4 = MIDI 69, convention C=0.
      final semitonesFromA4 = 12 * log(peak.frequencyHz / referenceA4Hz) / ln2;
      final midi = 69 + semitonesFromA4.round();
      final chromaIndex = ((midi % 12) + 12) % 12;

      chroma[chromaIndex] += log(1 + compressionGamma * peak.magnitude);
    }

    final peakEnergy = chroma.reduce(max);
    if (peakEnergy <= 0) return chroma; // aucun pic (silence) → vecteur nul
    for (int i = 0; i < 12; i++) {
      chroma[i] /= peakEnergy;
    }
    return chroma;
  }
}
