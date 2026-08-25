import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/domain/enums/chord_quality.dart';

void main() {
  group('ChordQuality — intervalles et suffixes', () {
    test('major : triade majeure, pas de suffixe', () {
      expect(ChordQuality.major.intervals, [0, 4, 7]);
      expect(ChordQuality.major.suffix, '');
    });

    test('minor : triade mineure, suffixe "m"', () {
      expect(ChordQuality.minor.intervals, [0, 3, 7]);
      expect(ChordQuality.minor.suffix, 'm');
    });

    test('dominant7 : 7e mineure ajoutée, suffixe "7"', () {
      expect(ChordQuality.dominant7.intervals, [0, 4, 7, 10]);
      expect(ChordQuality.dominant7.suffix, '7');
    });

    test('major7 : 7e majeure ajoutée, suffixe "maj7"', () {
      expect(ChordQuality.major7.intervals, [0, 4, 7, 11]);
      expect(ChordQuality.major7.suffix, 'maj7');
    });

    test('4 qualités exactement (US3 : 12 × 4 = 48 templates)', () {
      expect(ChordQuality.values, hasLength(4));
    });
  });
}
