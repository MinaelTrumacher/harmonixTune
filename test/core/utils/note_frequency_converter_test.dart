import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/core/constants/audio_constants.dart';
import 'package:harmonix_tune/core/utils/note_frequency_converter.dart';

void main() {
  group(
    'NoteFrequencyConverter — notes standard (accordage guitare E2-E4)',
    () {
      // Valeurs de référence : AudioConstants.stringFrequencies.
      const expected = {
        'E2': 82.41,
        'A2': 110.00,
        'D3': 146.83,
        'G3': 196.00,
        'B3': 246.94,
        'E4': 329.63,
      };

      for (final entry in expected.entries) {
        test('${entry.key} ≈ ${entry.value} Hz', () {
          final hz = NoteFrequencyConverter.toFrequencyHz(entry.key);
          expect(hz, isNotNull);
          expect(hz!, closeTo(entry.value, 0.1));
        });
      }

      test('A4 = référence exacte (440 Hz)', () {
        expect(
          NoteFrequencyConverter.toFrequencyHz('A4'),
          closeTo(AudioConstants.referenceA4Hz, 0.001),
        );
      });
    },
  );

  group('NoteFrequencyConverter — dièses et casse', () {
    test('C#3 est un demi-ton au-dessus de C3', () {
      final c3 = NoteFrequencyConverter.toFrequencyHz('C3')!;
      final cSharp3 = NoteFrequencyConverter.toFrequencyHz('C#3')!;
      expect(cSharp3 / c3, closeTo(1.05946, 0.0005)); // 2^(1/12)
    });

    test('accepte les lettres minuscules', () {
      expect(NoteFrequencyConverter.toFrequencyHz('e2'), closeTo(82.41, 0.1));
    });

    test('accepte les octaves négatives (notation scientifique)', () {
      expect(NoteFrequencyConverter.toFrequencyHz('C-1'), isNotNull);
    });
  });

  group('NoteFrequencyConverter — formats invalides', () {
    test('retourne null sans octave', () {
      expect(NoteFrequencyConverter.toFrequencyHz('E'), isNull);
    });

    test('retourne null pour une lettre hors A-G', () {
      expect(NoteFrequencyConverter.toFrequencyHz('H2'), isNull);
    });

    test('retourne null pour une chaîne vide', () {
      expect(NoteFrequencyConverter.toFrequencyHz(''), isNull);
    });

    test('retourne null pour un texte quelconque', () {
      expect(NoteFrequencyConverter.toFrequencyHz('open-g'), isNull);
    });
  });
}
