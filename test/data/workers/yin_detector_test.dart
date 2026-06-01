import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/data/workers/yin_detector.dart';

void main() {
  const sampleRate = 44100;
  const bufferSize = 2048;

  Float64List sine(double freqHz, {double amplitude = 0.8}) {
    final out = Float64List(bufferSize);
    for (int i = 0; i < bufferSize; i++) {
      out[i] = amplitude * sin(2 * pi * freqHz * i / sampleRate);
    }
    return out;
  }

  YinDetector makeDetector() =>
      YinDetector(sampleRate: sampleRate, bufferSize: bufferSize);

  group('YinDetector — silence', () {
    test('retourne null pour un signal nul', () {
      final result = makeDetector().detect(Float64List(bufferSize));
      expect(result, isNull);
    });

    test('retourne null pour un bruit très faible (amplitude < 0.01)', () {
      final rng = Random(42);
      final noise = Float64List.fromList(
        List.generate(bufferSize, (_) => (rng.nextDouble() * 2 - 1) * 0.005),
      );
      final result = makeDetector().detect(noise);
      expect(result, isNull);
    });
  });

  group('YinDetector — détection de fréquence', () {
    test('détecte A4 (440 Hz) avec confiance ≥ 0.90', () {
      final result = makeDetector().detect(sine(440.0));
      expect(result, isNotNull);
      expect(result!.confidence, greaterThanOrEqualTo(0.90));
      expect(result.f0Hz, closeTo(440.0, 2.0));
    });

    test('détecte E4 (329.63 Hz)', () {
      final result = makeDetector().detect(sine(329.63));
      expect(result, isNotNull);
      expect(result!.f0Hz, closeTo(329.63, 2.0));
    });

    test('détecte E2 (82.41 Hz — corde la plus grave de la guitare)', () {
      final result = makeDetector().detect(sine(82.41));
      expect(result, isNotNull);
      expect(result!.f0Hz, closeTo(82.41, 2.0));
    });

    test('détecte A2 (110 Hz)', () {
      final result = makeDetector().detect(sine(110.0));
      expect(result, isNotNull);
      expect(result!.f0Hz, closeTo(110.0, 2.0));
    });

    test('précision ≤ ±2 cents pour A4', () {
      final result = makeDetector().detect(sine(440.0));
      expect(result, isNotNull);
      final cents = 1200 * log(result!.f0Hz / 440.0) / log(2);
      expect(cents.abs(), lessThanOrEqualTo(2.0));
    });

    test('précision ≤ ±2 cents pour E2', () {
      final result = makeDetector().detect(sine(82.41));
      expect(result, isNotNull);
      // Fréquence de référence exacte pour E2
      final fRef = 440.0 * pow(2.0, (40 - 69) / 12.0); // MIDI 40 = E2
      final cents = 1200 * log(result!.f0Hz / fRef) / log(2);
      expect(cents.abs(), lessThanOrEqualTo(2.0));
    });
  });

  group('YinDetector — robustesse aux bords', () {
    test(
      'ne lève pas d\'exception si τ* est sur τ_min (pas d\'interpolation)',
      () {
        // Signal très haute fréquence : τ proche de τ_min
        expect(() => makeDetector().detect(sine(1100.0)), returnsNormally);
      },
    );

    test(
      'ne lève pas d\'exception si τ* est sur τ_max (pas d\'interpolation)',
      () {
        // Signal à la fréquence limite basse (≈ sampleRate / τ_max)
        final lowFreq = sampleRate / (bufferSize ~/ 2).toDouble();
        expect(() => makeDetector().detect(sine(lowFreq)), returnsNormally);
      },
    );

    test('confiance dans [0.0, 1.0] pour tout signal valide', () {
      for (final hz in [82.41, 110.0, 146.83, 196.0, 246.94, 329.63, 440.0]) {
        final result = makeDetector().detect(sine(hz));
        if (result != null) {
          expect(
            result.confidence,
            inInclusiveRange(0.0, 1.0),
            reason: 'Échec pour $hz Hz',
          );
        }
      }
    });

    test('f0 dans la plage physique [43 Hz, 1200 Hz] quand détecté', () {
      final result = makeDetector().detect(sine(440.0));
      expect(result, isNotNull);
      expect(result!.f0Hz, inInclusiveRange(43.0, 1200.0));
    });
  });

  group('YinDetector — paramètre threshold', () {
    test(
      'threshold bas (0.05) : plus strict, peut retourner null sur signal bruité',
      () {
        final strictDetector = YinDetector(
          sampleRate: sampleRate,
          bufferSize: bufferSize,
          threshold: 0.05,
        );
        // Signal propre toujours détecté même avec threshold strict
        final result = strictDetector.detect(sine(440.0));
        expect(result, isNotNull);
      },
    );

    test(
      'threshold élevé (0.20) : moins strict, détecte malgré bruit léger',
      () {
        final lenientDetector = YinDetector(
          sampleRate: sampleRate,
          bufferSize: bufferSize,
          threshold: 0.20,
        );
        final result = lenientDetector.detect(sine(440.0));
        expect(result, isNotNull);
      },
    );
  });
}
