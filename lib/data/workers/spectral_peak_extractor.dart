import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Un pic spectral détecté : fréquence affinée par interpolation parabolique
/// et magnitude brute au bin entier le plus proche.
class SpectralPeak {
  const SpectralPeak({required this.frequencyHz, required this.magnitude});

  final double frequencyHz;
  final double magnitude;
}

/// Extrait les pics spectraux d'un buffer audio par FFT (US3 — détection
/// d'accords).
///
/// Fenêtrage de Hann + FFT via `fftea`, filtrage de la bande passante
/// [minFreqHz, maxFreqHz] (exclut le bin DC et le bruit hors registre
/// musical), détection de maxima locaux, et affinage de chaque pic par
/// interpolation parabolique — compense la résolution grossière des bins FFT
/// dans le registre grave.
class SpectralPeakExtractor {
  SpectralPeakExtractor({
    required this.sampleRate,
    required this.fftSize,
    this.minFreqHz = 70.0,
    this.maxFreqHz = 3000.0,
  }) : _fft = FFT(fftSize),
       _window = Window.hanning(fftSize);

  final int sampleRate;
  final int fftSize;
  final double minFreqHz;
  final double maxFreqHz;

  final FFT _fft;
  final Float64List _window;

  /// [samples] doit contenir exactement [fftSize] échantillons PCM normalisés
  /// [-1.0, 1.0].
  List<SpectralPeak> extract(Float64List samples) {
    assert(samples.length == fftSize, 'samples doit avoir fftSize éléments');

    final windowed = _window.applyWindowReal(samples);
    final spectrum = _fft.realFft(windowed).discardConjugates().magnitudes();

    // Bin 0 (DC) exclu ; bande bornée à [minFreqHz, maxFreqHz] AVANT le
    // peak-picking pour ne pas laisser un artefact basse fréquence fausser
    // l'interpolation parabolique du premier pic grave valide.
    final minBin = max(1, (minFreqHz * fftSize / sampleRate).ceil());
    final maxBin = min(
      spectrum.length - 2,
      (maxFreqHz * fftSize / sampleRate).floor(),
    );

    final peaks = <SpectralPeak>[];
    for (int bin = minBin; bin <= maxBin; bin++) {
      final d0 = spectrum[bin - 1];
      final d1 = spectrum[bin];
      final d2 = spectrum[bin + 1];
      // Maximum local strict (évite les doublons sur un plateau).
      if (d1 <= d0 || d1 <= d2) continue;

      // Interpolation parabolique — même formule que YinDetector._findTauStar
      // (garde sur le dénominateur pour éviter une division quasi nulle).
      final denom = 2.0 * (d0 - 2.0 * d1 + d2);
      final refinedBin = denom.abs() > 1e-10 ? bin + (d0 - d2) / denom : bin;

      peaks.add(
        SpectralPeak(
          frequencyHz: refinedBin * sampleRate / fftSize,
          magnitude: d1,
        ),
      );
    }
    return peaks;
  }
}
