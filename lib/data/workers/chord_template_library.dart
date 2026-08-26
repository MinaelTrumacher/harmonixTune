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
  ///
  /// [complexityMargin] : rasoir d'Occam musical. Un template à 4 notes
  /// (7, maj7) est un sur-ensemble d'intervalles de la triade majeure de
  /// même racine — il "accroche" donc plus facilement le résidu harmonique
  /// (5e/7e harmonique d'une fondamentale) que la triade seule. Si le
  /// meilleur score brut est un template à 4 notes mais que son "parent" à
  /// 3 notes reste à moins de [complexityMargin] derrière, la triade plus
  /// simple l'emporte quand même.
  static ({String chordName, double confidence}) match(
    List<double> chroma, {
    required double complexityMargin,
  }) {
    assert(chroma.length == 12, 'chroma doit être un vecteur 12D');

    ChordTemplate bestTemplate = templates.first;
    double bestScore = -1.0;
    for (final template in templates) {
      final score = _cosineSimilarity(chroma, template.vector);
      if (score > bestScore) {
        bestScore = score;
        bestTemplate = template;
      }
    }

    // Un seul "parent" plus simple possible par template dans le jeu de 4
    // qualités actuel (major/minor n'ont pas de parent ; 7 et maj7 ont
    // chacun major pour unique parent) — pas de recherche du parent le plus
    // proche en cas de chaîne à plusieurs niveaux, qui n'existe pas ici.
    for (final candidate in templates) {
      if (identical(candidate, bestTemplate)) continue;
      if (!_isStrictSubset(candidate.vector, bestTemplate.vector)) continue;
      final candidateScore = _cosineSimilarity(chroma, candidate.vector);
      if (bestScore - candidateScore < complexityMargin) {
        bestTemplate = candidate;
        bestScore = candidateScore;
      }
      break;
    }

    return (chordName: bestTemplate.name, confidence: bestScore);
  }

  /// `true` si les degrés actifs de [a] forment un sous-ensemble strict de
  /// ceux de [b] (ex. triade majeure {0,4,7} ⊂ dominante 7 {0,4,7,10}).
  static bool _isStrictSubset(List<double> a, List<double> b) {
    int activeInA = 0;
    int activeInB = 0;
    for (int i = 0; i < 12; i++) {
      if (a[i] > 0) {
        activeInA++;
        if (b[i] <= 0) return false;
      }
      if (b[i] > 0) activeInB++;
    }
    return activeInA < activeInB;
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
