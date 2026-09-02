import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/core/utils/note_frequency_converter.dart';
import 'package:harmonix_tune/data/workers/chromagram_builder.dart';
import 'package:harmonix_tune/data/workers/spectral_peak_extractor.dart';

void main() {
  const referenceA4Hz = 440.0;

  double hz(String note) => NoteFrequencyConverter.toFrequencyHz(note)!;

  group('ChromagramBuilder — cas de base', () {
    test('aucun pic → vecteur nul (silence)', () {
      final chroma = ChromagramBuilder.build(
        [],
        referenceA4Hz: referenceA4Hz,
        compressionGamma: 10.0,
      );
      expect(chroma, hasLength(12));
      expect(chroma.every((v) => v == 0.0), isTrue);
    });

    test('un seul pic → un seul degré chromatique actif, normalisé à 1.0', () {
      final chroma = ChromagramBuilder.build(
        [SpectralPeak(frequencyHz: hz('A4'), magnitude: 1.0)],
        referenceA4Hz: referenceA4Hz,
        compressionGamma: 10.0,
      );
      expect(chroma[9], closeTo(1.0, 1e-9)); // A = index 9
      expect(chroma.where((v) => v > 0), hasLength(1));
    });
  });

  group('ChromagramBuilder — repliement (convention MIDI C=0)', () {
    test('accord Do majeur (C4,E4,G4) → degrés 0,4,7 actifs', () {
      final chroma = ChromagramBuilder.build(
        [
          SpectralPeak(frequencyHz: hz('C4'), magnitude: 1.0),
          SpectralPeak(frequencyHz: hz('E4'), magnitude: 1.0),
          SpectralPeak(frequencyHz: hz('G4'), magnitude: 1.0),
        ],
        referenceA4Hz: referenceA4Hz,
        compressionGamma: 10.0,
      );

      expect(chroma[0], greaterThan(0)); // C
      expect(chroma[4], greaterThan(0)); // E
      expect(chroma[7], greaterThan(0)); // G
      for (final i in [1, 2, 3, 5, 6, 8, 9, 10, 11]) {
        expect(chroma[i], 0.0, reason: 'index $i ne doit pas être actif');
      }
    });

    test('même note à des octaves différentes → replié sur le même degré', () {
      final chroma = ChromagramBuilder.build(
        [
          SpectralPeak(frequencyHz: hz('C2'), magnitude: 1.0),
          SpectralPeak(frequencyHz: hz('C4'), magnitude: 1.0),
          SpectralPeak(frequencyHz: hz('C6'), magnitude: 1.0),
        ],
        referenceA4Hz: referenceA4Hz,
        compressionGamma: 10.0,
      );

      expect(chroma.where((v) => v > 0), hasLength(1));
      expect(chroma[0], closeTo(1.0, 1e-9));
    });
  });

  group('ChromagramBuilder — compression log (§ cadrage US3)', () {
    test(
      'une note à forte attaque n\'écrase pas totalement une note faible',
      () {
        final chroma = ChromagramBuilder.build(
          [
            SpectralPeak(
              frequencyHz: hz('C4'),
              magnitude: 100.0,
            ), // attaque forte
            SpectralPeak(
              frequencyHz: hz('G4'),
              magnitude: 1.0,
            ), // sustain faible
          ],
          referenceA4Hz: referenceA4Hz,
          compressionGamma: 10.0,
        );

        // Sans compression (mise à l'échelle linéaire), le ratio quiet/loud
        // serait 1/100 = 0.01. La compression log(1+γx) le remonte largement.
        final ratio = chroma[7] / chroma[0]; // G / C
        expect(ratio, greaterThan(0.3));
        expect(ratio, lessThan(1.0));
      },
    );
  });
}
