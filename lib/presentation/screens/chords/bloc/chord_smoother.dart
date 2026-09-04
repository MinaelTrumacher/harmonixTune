import '../../../../core/constants/audio_constants.dart';
import '../../../../domain/entities/chord_result.dart';

/// Ce que l'IHM doit afficher pour un [SmoothedChord] donné.
///
/// [silent] : aucun accord résolu à montrer (avant le premier onset, ou
/// après le timeout de silence prolongé). [indeterminate] : un événement est
/// en cours (attaque, ou pas encore assez de votes fiables) mais rien n'a
/// encore été résolu — état transitoire, seulement visible s'il n'y a rien
/// à tenir en attendant. [detected] : un accord a été résolu pour
/// l'événement en cours ou le précédent, avec sa confiance moyenne.
enum SmoothedChordKind { silent, indeterminate, detected }

class SmoothedChord {
  const SmoothedChord({required this.kind, required this.result});

  final SmoothedChordKind kind;

  /// Le `ChordResult` à afficher. Pour [detected], le nom résolu et sa
  /// confiance moyenne sur les frames qui le soutiennent ; le
  /// `chromaVector`/`activeNoteIndices` restent ceux de la frame la plus
  /// récente (pour un retour visuel toujours à jour, même une fois le nom
  /// figé).
  final ChordResult result;
}

/// Segmentation par événement (onset) + vote pondéré par famille — US3.
///
/// Un strum de guitare est un événement discret (attaque → sustain →
/// decay → silence), pas un flux continu à lisser frame par frame — cf.
/// §11 de `docs/STRATEGIE_DETECTION_ACCORDS.md` pour le diagnostic initial
/// (flottement pendant l'attaque, disparition prématurée sur la decay).
///
/// Le vote lui-même (§13) ne compte plus les noms exacts à égalité : il
/// pondère par confiance cumulée sur une fenêtre glissante de
/// [voteWindowSize] frames, regroupées par **famille** (racine + majeur/
/// mineur, sans 7e — `ChordResult.familyName`). Une variante à 7e (7,
/// maj7) ne détrône la triade de base de sa famille que si son écart moyen
/// dépasse [complexityMargin] **et** qu'elle est soutenue par au moins la
/// moitié des frames de la fenêtre — pas sur un pic isolé.
///
/// Règles :
/// - **Onset** : une frame non-silencieuse qui suit un événement clos
///   démarre un nouvel événement. Les [attackFramesToSkip] premières
///   frames ne participent pas au vote (transitoire d'attaque du
///   médiator) — l'affichage précédent reste visible pendant ce temps.
/// - **Vote** : à partir de la frame suivante, chaque résultat de confiance
///   suffisante alimente la fenêtre glissante ; l'affichage se met à jour
///   en direct sur la décision recalculée à chaque frame.
/// - **Clôture** : [eventCloseSilentFrames] frames silencieuses
///   consécutives closent l'événement — un creux d'une ou deux frames
///   (battement harmonique de la corde) ne suffit pas.
/// - **Persistance** : l'accord résolu reste affiché après la clôture,
///   jusqu'au prochain onset, avec un filet de sécurité :
///   [silenceTimeoutFrames] de silence total réinitialisent doucement
///   l'affichage sur l'état silencieux.
class ChordSmoother {
  ChordSmoother({
    this.attackFramesToSkip = AudioConstants.chordAttackFramesToSkip,
    this.eventCloseSilentFrames = AudioConstants.chordEventCloseSilentFrames,
    this.silenceTimeoutFrames = AudioConstants.chordSilenceTimeoutFrames,
    this.minConfidence = AudioConstants.chordMinConfidence,
    this.voteWindowSize = AudioConstants.chordVoteWindowSize,
    this.complexityMargin = AudioConstants.chordComplexityMargin,
  });

  final int attackFramesToSkip;
  final int eventCloseSilentFrames;
  final int silenceTimeoutFrames;
  final double minConfidence;
  final int voteWindowSize;
  final double complexityMargin;

  int _consecutiveSilentFrames = 0;
  int _framesSinceOnset = 0;
  final List<ChordResult> _window = [];
  SmoothedChord? _held;

  bool get _eventClosed => _consecutiveSilentFrames >= eventCloseSilentFrames;

  /// Traite un nouveau `ChordResult` brut et retourne l'état à afficher.
  SmoothedChord push(ChordResult raw) {
    final isSilent = raw.chordName == ChordResult.silent.chordName;

    if (isSilent) {
      _consecutiveSilentFrames++;
      if (_consecutiveSilentFrames >= silenceTimeoutFrames) {
        _held = null;
      }
      return _held ??
          SmoothedChord(kind: SmoothedChordKind.silent, result: raw);
    }

    // Nouvel onset : l'événement précédent était clos (ou c'est la toute
    // première frame jouée depuis le démarrage/un reset) → fenêtre vidée.
    // Un simple creux (< eventCloseSilentFrames) ne ferme pas l'événement
    // en cours, donc ne déclenche pas ce reset.
    if (_eventClosed) {
      _framesSinceOnset = 0;
      _window.clear();
    }
    _consecutiveSilentFrames = 0;
    _framesSinceOnset++;

    if (_framesSinceOnset <= attackFramesToSkip) {
      // Transitoire d'attaque : pas encore de vote. Rien de plus fiable à
      // montrer que ce qu'on affichait déjà.
      return _held ??
          SmoothedChord(kind: SmoothedChordKind.indeterminate, result: raw);
    }

    _window.add(raw);
    while (_window.length > voteWindowSize) {
      _window.removeAt(0);
    }

    final decision = _decide(raw);
    if (decision == null) {
      return _held ??
          SmoothedChord(kind: SmoothedChordKind.indeterminate, result: raw);
    }
    _held = decision;
    return decision;
  }

  /// Recalcule la décision à partir de la fenêtre glissante courante, ou
  /// `null` si aucune frame de la fenêtre n'atteint [minConfidence].
  SmoothedChord? _decide(ChordResult latestRaw) {
    final familySums = <String, double>{};
    final familyFrameCounts = <String, int>{};
    final nameSums = <String, double>{};
    final nameFrameCounts = <String, int>{};
    final nameToFamily = <String, String>{};

    for (final r in _window) {
      if (r.confidence < minConfidence) continue;
      familySums[r.familyName] = (familySums[r.familyName] ?? 0) + r.confidence;
      familyFrameCounts[r.familyName] =
          (familyFrameCounts[r.familyName] ?? 0) + 1;
      nameSums[r.chordName] = (nameSums[r.chordName] ?? 0) + r.confidence;
      nameFrameCounts[r.chordName] = (nameFrameCounts[r.chordName] ?? 0) + 1;
      nameToFamily[r.chordName] = r.familyName;
    }
    if (familySums.isEmpty) return null;

    // Famille gagnante : moyenne la plus haute sur la fenêtre COMPLÈTE
    // (dénominateur fixe = voteWindowSize, pas le nombre de frames de cette
    // famille) — une famille qui n'apparaît que sur une frame isolée reste
    // diluée par les autres frames de la fenêtre.
    String bestFamily = familySums.keys.first;
    double bestFamilyAvg = -1;
    for (final entry in familySums.entries) {
      final avg = entry.value / voteWindowSize;
      if (avg > bestFamilyAvg) {
        bestFamilyAvg = avg;
        bestFamily = entry.key;
      }
    }

    // Au sein de la famille gagnante : la triade de base (nom == famille)
    // l'emporte par défaut. Une variante à 7e ne la détrône que si (a) son
    // écart moyen dépasse complexityMargin ET (b) elle est soutenue par au
    // moins la moitié des frames de la fenêtre — les deux critères
    // ensemble empêchent un pic isolé de suffire.
    final plainName = bestFamily;
    final plainAvg = (nameSums[plainName] ?? 0) / voteWindowSize;
    final requiredSupportFrames = (voteWindowSize / 2).ceil();

    String winningName = plainName;
    double winningAvg = plainAvg;
    for (final name in nameSums.keys) {
      if (name == plainName) continue;
      if (nameToFamily[name] != bestFamily) continue;
      final avg = nameSums[name]! / voteWindowSize;
      final supportFrames = nameFrameCounts[name] ?? 0;
      if (avg - plainAvg >= complexityMargin &&
          supportFrames >= requiredSupportFrames &&
          avg > winningAvg) {
        winningAvg = avg;
        winningName = name;
      }
    }

    // Confiance affichée : moyenne parmi les frames qui soutenaient
    // effectivement ce nom précis — plus intuitif pour l'utilisateur qu'une
    // moyenne diluée par la taille de la fenêtre. Cas limite : la triade de
    // base peut n'être JAMAIS apparue directement dans la fenêtre (seules
    // ses variantes à 7e y figurent, bloquées par le garde-fou de
    // persistance) — on retombe alors sur la moyenne de toute la famille.
    final winningNameSum = nameSums[winningName];
    final winningNameCount = nameFrameCounts[winningName];
    final displayConfidence =
        (winningNameSum != null && winningNameCount != null)
        ? winningNameSum / winningNameCount
        : familySums[bestFamily]! / familyFrameCounts[bestFamily]!;

    return SmoothedChord(
      kind: SmoothedChordKind.detected,
      result: ChordResult(
        chordName: winningName,
        familyName: bestFamily,
        chromaVector: latestRaw.chromaVector,
        confidence: displayConfidence,
        activeNoteIndices: latestRaw.activeNoteIndices,
      ),
    );
  }
}
