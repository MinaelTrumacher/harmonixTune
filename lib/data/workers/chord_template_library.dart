import 'dart:math';

import '../../core/utils/note_frequency_converter.dart';
import '../../domain/enums/chord_quality.dart';

/// Un accord de référence : nom affiché + vecteur chroma binaire (12D, 1.0
/// sur les degrés de l'accord, 0.0 ailleurs).
class ChordTemplate {
  const ChordTemplate({required this.name, required this.vector});

  final String name;
  final List<double> vector;
}

/// Génère les 48 templates d'accords (12 racines × 4 qualités) et matche un
/// chromagramme observé par similitude cosinus (US3).
///
/// Générés par rotation plutôt que codés en dur : garantit la cohérence des
/// 48 vecteurs et évite les erreurs de recopie.
abstract final class ChordTemplateLibrary {
  static final List<ChordTemplate> templates = _generateTemplates();

  static List<ChordTemplate> _generateTemplates() {
    final generated = <ChordTemplate>[];
    for (int root = 0; root < 12; root++) {
      for (final quality in ChordQuality.values) {
        final vector = List<double>.filled(12, 0.0);
        for (final interval in quality.intervals) {
          vector[(root + interval) % 12] = 1.0;
        }
        generated.add(
          ChordTemplate(
            name: '${NoteFrequencyConverter.chromaticScale[root]}'
                '${quality.suffix}',
            vector: vector,
          ),
        );
      }
    }
    return generated;
  }

  /// Retourne le template le mieux corrélé à [chroma] (vecteur 12D, énergie
  /// non-négative) et le score de similitude cosinus associé ([0.0, 1.0]).
  ///
  /// Ne fait aucune hypothèse de seuil de confiance — c'est à l'appelant
  /// (Isolate/BLoC) de décider, via `AudioConstants.chordMinConfidence`,
  /// si le score est suffisant pour afficher l'accord.
  static ({String chordName, double confidence}) match(List<double> chroma) {
    assert(chroma.length == 12, 'chroma doit être un vecteur 12D');

    String bestName = templates.first.name;
    double bestScore = -1.0;
    for (final template in templates) {
      final score = _cosineSimilarity(chroma, template.vector);
      if (score > bestScore) {
        bestScore = score;
        bestName = template.name;
      }
    }
    return (chordName: bestName, confidence: bestScore);
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < 12; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
