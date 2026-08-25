import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonix_tune/data/workers/chord_template_library.dart';

// Reproduit localement la formule de similitude cosinus (indépendamment de
// l'implémentation privée de ChordTemplateLibrary) pour vérifier des
// propriétés attendues des templates générés.
double _cosine(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB));
}

ChordTemplate _byName(String name) =>
    ChordTemplateLibrary.templates.firstWhere((t) => t.name == name);

void main() {
  group('ChordTemplateLibrary — génération', () {
    test('48 templates (12 racines × 4 qualités)', () {
      expect(ChordTemplateLibrary.templates, hasLength(48));
    });

    test('noms uniques', () {
      final names = ChordTemplateLibrary.templates.map((t) => t.name).toSet();
      expect(names, hasLength(48));
    });

    test('contient les 12 racines pour chaque qualité', () {
      const roots = [
        'C',
        'C#',
        'D',
        'D#',
        'E',
        'F',
        'F#',
        'G',
        'G#',
        'A',
        'A#',
        'B',
      ];
      for (final root in roots) {
        expect(ChordTemplateLibrary.templates.map((t) => t.name), contains(root)); // majeur
        expect(ChordTemplateLibrary.templates.map((t) => t.name), contains('${root}m'));
        expect(ChordTemplateLibrary.templates.map((t) => t.name), contains('${root}7'));
        expect(ChordTemplateLibrary.templates.map((t) => t.name), contains('${root}maj7'));
      }
    });

    test('vecteur "C" a exactement 3 degrés actifs (C, E, G)', () {
      final c = _byName('C');
      expect(c.vector[0], 1.0); // C
      expect(c.vector[4], 1.0); // E
      expect(c.vector[7], 1.0); // G
      expect(c.vector.where((v) => v == 1.0), hasLength(3));
    });

    test('vecteur "Am" a exactement 3 degrés actifs (A, C, E)', () {
      final am = _byName('Am');
      expect(am.vector[9], 1.0); // A
      expect(am.vector[0], 1.0); // C
      expect(am.vector[4], 1.0); // E
      expect(am.vector.where((v) => v == 1.0), hasLength(3));
    });
  });

  group('ChordTemplateLibrary — match()', () {
    test('accord C majeur pur → "C" avec confiance 1.0', () {
      final chroma = List<double>.filled(12, 0.0);
      chroma[0] = 1.0; // C
      chroma[4] = 1.0; // E
      chroma[7] = 1.0; // G

      final result = ChordTemplateLibrary.match(chroma);
      expect(result.chordName, 'C');
      expect(result.confidence, closeTo(1.0, 1e-9));
    });

    test('accord La mineur pur → "Am" avec confiance 1.0', () {
      final chroma = List<double>.filled(12, 0.0);
      chroma[9] = 1.0; // A
      chroma[0] = 1.0; // C
      chroma[4] = 1.0; // E

      final result = ChordTemplateLibrary.match(chroma);
      expect(result.chordName, 'Am');
      expect(result.confidence, closeTo(1.0, 1e-9));
    });

    test('silence (vecteur nul) → confiance 0.0, pas d\'exception', () {
      final result = ChordTemplateLibrary.match(List<double>.filled(12, 0.0));
      expect(result.confidence, 0.0);
    });

    test(
      'ambiguïté relatif majeur/mineur (C vs Am) : cosine ≈ 0.667 — '
      'justifie chordMinConfidence = 0.65',
      () {
        final c = _byName('C');
        final am = _byName('Am');
        expect(_cosine(c.vector, am.vector), closeTo(2 / 3, 1e-9));
      },
    );
  });
}
