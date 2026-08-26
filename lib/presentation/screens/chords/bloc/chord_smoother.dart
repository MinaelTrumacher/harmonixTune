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
  /// confiance moyenne sur l'événement ; le `chromaVector`/
  /// `activeNoteIndices` restent ceux de la frame la plus récente (pour un
  /// retour visuel toujours à jour, même une fois le nom figé).
  final ChordResult result;
}

/// Segmentation par événement (onset) — US3.
///
/// Un strum de guitare est un événement discret (attaque → sustain →
/// decay → silence), pas un flux continu à lisser frame par frame : lisser
/// en continu revient à moyenner l'attaque (transitoire peu fiable) avec le
/// sustain (signal utile) à égalité, ce qui produit le flottement observé
/// en recette (ex. un Fmaj7 qui s'affiche brièvement "G7", "A7" avant de se
/// stabiliser, puis qui disparaît dès que le volume retombe sous le seuil
/// de silence alors que la note résonne encore).
///
/// Règles :
/// - **Onset** : une frame non-silencieuse qui suit un événement clos
///   démarre un nouvel événement. Les [attackFramesToSkip] premières frames
///   ne participent pas au vote (transitoire d'attaque du médiator) —
///   l'affichage précédent reste visible pendant ce temps, il ne
///   redescend jamais sur "Indéterminé" tant qu'il y a quelque chose à
///   montrer.
/// - **Vote** : à partir de la frame suivante, chaque résultat de confiance
///   suffisante vote pour son nom d'accord ; l'affichage se met à jour en
///   direct sur le nom majoritaire cumulé et sa confiance moyenne.
/// - **Clôture** : [eventCloseSilentFrames] frames silencieuses
///   consécutives closent l'événement — un creux d'une ou deux frames
///   (battement harmonique de la corde) ne suffit pas, pour ne pas couper
///   une note qui résonne encore.
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
  });

  final int attackFramesToSkip;
  final int eventCloseSilentFrames;
  final int silenceTimeoutFrames;
  final double minConfidence;

  int _consecutiveSilentFrames = 0;
  int _framesSinceOnset = 0;
  final Map<String, int> _votes = {};
  final Map<String, double> _voteConfidenceSum = {};
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
    // première frame jouée depuis le démarrage/un reset) → on repart de
    // zéro pour le vote. Un simple creux (< eventCloseSilentFrames) ne
    // ferme pas l'événement en cours, donc ne déclenche pas ce reset.
    if (_eventClosed) {
      _framesSinceOnset = 0;
      _votes.clear();
      _voteConfidenceSum.clear();
    }
    _consecutiveSilentFrames = 0;
    _framesSinceOnset++;

    if (_framesSinceOnset <= attackFramesToSkip) {
      // Transitoire d'attaque : pas encore de vote. Rien de plus fiable à
      // montrer que ce qu'on affichait déjà.
      return _held ??
          SmoothedChord(kind: SmoothedChordKind.indeterminate, result: raw);
    }

    if (raw.confidence >= minConfidence) {
      _votes[raw.chordName] = (_votes[raw.chordName] ?? 0) + 1;
      _voteConfidenceSum[raw.chordName] =
          (_voteConfidenceSum[raw.chordName] ?? 0) + raw.confidence;
    }

    if (_votes.isEmpty) {
      return _held ??
          SmoothedChord(kind: SmoothedChordKind.indeterminate, result: raw);
    }

    final leader = _votes.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    final display = SmoothedChord(
      kind: SmoothedChordKind.detected,
      result: ChordResult(
        chordName: leader.key,
        chromaVector: raw.chromaVector,
        confidence: _voteConfidenceSum[leader.key]! / leader.value,
        activeNoteIndices: raw.activeNoteIndices,
      ),
    );
    _held = display;
    return display;
  }
}
