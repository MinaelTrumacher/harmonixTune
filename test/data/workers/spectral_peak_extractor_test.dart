import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/data/workers/spectral_peak_extractor.dart';

void main() {
  const sampleRate = 44100;
  const fftSize = 4096;

  Float64List sumOfSines(List<double> freqsHz, {double amplitude = 0.3}) {
    final out = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      double sample = 0.0;
      for (final f in freqsHz) {
        sample += amplitude * sin(2 * pi * f * i / sampleRate);
      }
      out[i] = sample;
    }
    return out;
  }

  SpectralPeakExtractor makeExtractor({
    double minFreqHz = 70.0,
    double maxFreqHz = 3000.0,
  }) => SpectralPeakExtractor(
    sampleRate: sampleRate,
    fftSize: fftSize,
    minFreqHz: minFreqHz,
    maxFreqHz: maxFreqHz,
  );

  group('SpectralPeakExtractor — silence', () {
    test('signal nul → aucun pic', () {
      final peaks = makeExtractor().extract(Float64List(fftSize));
      expect(peaks, isEmpty);
    });
  });

  group('SpectralPeakExtractor — détection & interpolation parabolique', () {
    test('sinusoïde pure 440 Hz → un pic proche de 440 Hz', () {
      final peaks = makeExtractor().extract(sumOfSines([440.0]));
      expect(peaks, isNotEmpty);
      final closest = peaks.reduce(
        (a, b) => (a.frequencyHz - 440.0).abs() < (b.frequencyHz - 440.0).abs()
            ? a
            : b,
      );
      // Résolution brute d'un bin ≈ 44100/4096 ≈ 10.77 Hz — l'interpolation
      // parabolique doit ramener l'erreur bien en dessous de cette valeur.
      expect(closest.frequencyHz, closeTo(440.0, 3.0));
      expect(closest.magnitude, greaterThan(0));
    });

    test('accord (3 sinusoïdes) → 3 pics distincts détectés', () {
      // Do majeur : C4, E4, G4.
      final peaks = makeExtractor().extract(
        sumOfSines([261.63, 329.63, 392.0]),
      );
      final freqs = peaks.map((p) => p.frequencyHz).toList();

      bool hasPeakNear(double target) =>
          freqs.any((f) => (f - target).abs() < 5.0);

      expect(hasPeakNear(261.63), isTrue, reason: 'pic manquant proche C4');
      expect(hasPeakNear(329.63), isTrue, reason: 'pic manquant proche E4');
      expect(hasPeakNear(392.0), isTrue, reason: 'pic manquant proche G4');
    });
  });

  group('SpectralPeakExtractor — bande passante [minFreqHz, maxFreqHz]', () {
    test('bin DC exclu (jamais de pic à 0 Hz)', () {
      final peaks = makeExtractor().extract(sumOfSines([220.0]));
      expect(peaks.any((p) => p.frequencyHz == 0), isFalse);
    });

    test('signal à 50 Hz (< 70 Hz) → aucun pic (ronflement secteur filtré)', () {
      final peaks = makeExtractor().extract(sumOfSines([50.0]));
      expect(peaks, isEmpty);
    });

    test('signal à 4000 Hz (> 3000 Hz) → aucun pic (souffle filtré)', () {
      final peaks = makeExtractor().extract(sumOfSines([4000.0]));
      expect(peaks, isEmpty);
    });
  });
}
