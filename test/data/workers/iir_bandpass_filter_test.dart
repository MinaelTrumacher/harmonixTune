import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/data/workers/iir_bandpass_filter.dart';

void main() {
  const sampleRate = 44100;
  const bufferSize = 4096; // buffer plus grand pour mesures spectrales fiables

  // Génère un signal sinusoïdal pur
  Float64List sine(double freqHz, {double amplitude = 1.0}) {
    final out = Float64List(bufferSize);
    for (int i = 0; i < bufferSize; i++) {
      out[i] = amplitude * sin(2 * pi * freqHz * i / sampleRate);
    }
    return out;
  }

  // Calcule la puissance RMS d'un signal (ignore les premiers échantillons
  // pour laisser le filtre converger vers son régime permanent).
  double rms(Float64List samples, {int skipFirst = 512}) {
    double sum = 0;
    final count = samples.length - skipFirst;
    for (int i = skipFirst; i < samples.length; i++) {
      sum += samples[i] * samples[i];
    }
    return sqrt(sum / count);
  }

  group('IirBandpassFilter — construction', () {
    test('s\'instancie sans exception', () {
      expect(
        () => IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate),
        returnsNormally,
      );
    });

    test('Q par défaut = 4.0', () {
      final f = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);
      expect(f.Q, equals(4.0));
    });

    test('accepte un Q personnalisé', () {
      final f = IirBandpassFilter(
        centerHz: 440.0,
        sampleRate: sampleRate,
        Q: 8.0,
      );
      expect(f.Q, equals(8.0));
    });
  });

  group('IirBandpassFilter — comportement fréquentiel', () {
    test('laisse passer le signal à la fréquence centrale (gain ≈ 1)', () {
      final filter = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);
      final signal = sine(440.0);
      final rmsIn = rms(signal);
      filter.process(signal);
      final rmsOut = rms(signal);
      // Le filtre passe-bande a un gain ≈ 1 à la fréquence centrale
      expect(rmsOut / rmsIn, greaterThan(0.7));
    });

    test('atténue fortement un signal loin de la fréquence centrale', () {
      // Centre : 440 Hz, signal testé : 82 Hz (plus de 2 octaves d'écart)
      final filter = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);
      final signal = sine(82.41);
      final rmsIn = rms(signal);
      filter.process(signal);
      final rmsOut = rms(signal);
      // Atténuation significative hors bande
      expect(rmsOut / rmsIn, lessThan(0.3));
    });

    test('atténue fortement les fréquences très éloignées (rapport > 10×)', () {
      final filter = IirBandpassFilter(centerHz: 110.0, sampleRate: sampleRate);
      // Signal à 440 Hz — 2 octaves au-dessus du centre
      final signal = sine(440.0);
      final rmsIn = rms(signal);
      filter.process(signal);
      final rmsOut = rms(signal);
      expect(rmsOut / rmsIn, lessThan(0.15));
    });

    test('signal nul en entrée → signal nul en sortie', () {
      final filter = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);
      final silence = Float64List(bufferSize);
      filter.process(silence);
      expect(silence.every((s) => s == 0.0), isTrue);
    });
  });

  group('IirBandpassFilter — updateCenter', () {
    test('updateCenter change la fréquence de passage', () {
      final filter = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);

      // Avant updateCenter : 110 Hz doit être atténué (centre=440)
      final sig1 = sine(110.0);
      final rmsIn = rms(sig1);
      filter.process(sig1);
      final rmsAfterFirst = rms(sig1);
      expect(rmsAfterFirst / rmsIn, lessThan(0.3));

      // Après updateCenter(110) : 110 Hz doit passer
      filter.updateCenter(110.0);
      final sig2 = sine(110.0);
      filter.process(sig2);
      final rmsAfterUpdate = rms(sig2);
      expect(rmsAfterUpdate / rms(sine(110.0)), greaterThan(0.7));
    });

    test(
      'updateCenter réinitialise l\'état du filtre (pas de transitoire persistant)',
      () {
        final filter = IirBandpassFilter(
          centerHz: 440.0,
          sampleRate: sampleRate,
        );
        // Alimenter le filtre avec un signal fort pour charger l'état interne
        filter.process(sine(440.0, amplitude: 10.0));

        // Changer de centre : l'état doit être réinitialisé
        filter.updateCenter(110.0);
        // Les premiers échantillons d'un signal nul doivent être nuls (pas de rémanence)
        final silence = Float64List(64);
        filter.process(silence);
        for (final s in silence) {
          expect(s, closeTo(0.0, 1e-10));
        }
      },
    );
  });

  group('IirBandpassFilter — stabilité numérique', () {
    test('ne diverge pas sur 10 000 échantillons à plein gain', () {
      final filter = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);
      final longSignal = Float64List(10000);
      for (int i = 0; i < longSignal.length; i++) {
        longSignal[i] = sin(2 * pi * 440.0 * i / sampleRate);
      }
      filter.process(longSignal);
      // Aucune valeur ne doit être infinie ou NaN
      expect(longSignal.any((s) => s.isNaN || s.isInfinite), isFalse);
      // Amplitude bornée (le filtre est stable)
      expect(longSignal.every((s) => s.abs() <= 10.0), isTrue);
    });

    test(
      'traite les fréquences graves des cordes de guitare sans divergence',
      () {
        // Fréquences des 6 cordes en accord standard
        const stringFreqs = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];
        for (final freq in stringFreqs) {
          final filter = IirBandpassFilter(
            centerHz: freq,
            sampleRate: sampleRate,
          );
          final signal = sine(freq);
          filter.process(signal);
          expect(
            signal.any((s) => s.isNaN || s.isInfinite),
            isFalse,
            reason: 'Divergence pour $freq Hz',
          );
        }
      },
    );
  });

  group('IirBandpassFilter — process in-place', () {
    test('modifie le tableau passé en paramètre (in-place)', () {
      final filter = IirBandpassFilter(centerHz: 440.0, sampleRate: sampleRate);
      final signal = sine(440.0);
      final original = Float64List.fromList(signal);
      filter.process(signal);
      // Le tableau doit avoir été modifié
      bool changed = false;
      for (int i = 0; i < signal.length; i++) {
        if ((signal[i] - original[i]).abs() > 1e-10) {
          changed = true;
          break;
        }
      }
      expect(changed, isTrue);
    });
  });
}
