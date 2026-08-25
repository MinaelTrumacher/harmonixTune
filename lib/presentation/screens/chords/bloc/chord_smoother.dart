import '../../../../core/constants/audio_constants.dart';
import '../../../../domain/entities/chord_result.dart';

/// Ce que l'IHM doit afficher pour un [SmoothedChord] donné.
///
/// Distinct de `ChordResult.chordName == '--'` : le silence est un état
/// technique immédiat (RMS sous seuil), l'indétermination est un état
/// musical (signal présent mais aucun accord fiable) atteint seulement
/// après [AudioConstants.chordHoldFramesOnIndetermination] fenêtres
/// d'hésitation — cf. § 5.2 de `docs/STRATEGIE_DETECTION_ACCORDS.md`.
enum SmoothedChordKind { silent, indeterminate, detected }

class SmoothedChord {
  const SmoothedChord({required this.kind, required this.result});

  final SmoothedChordKind kind;

  /// Le `ChordResult` à afficher : l'accord confirmé pour [detected], le
  /// dernier accord confirmé tenu à l'écran pendant le hold pour
  /// [indeterminate], ou `ChordResult.silent` pour [silent].
  final ChordResult result;
}

/// Filtre anti-scintillement (US3) : transforme le flux de `ChordResult`
/// bruts émis frame par frame par l'Isolate en une séquence stable de
/// [SmoothedChord] pour l'affichage.
///
/// Règles (§ 5.2 de la stratégie) :
/// - Silence : état immédiat, sans hold — pas d'hésitation à gérer, le seuil
///   RMS est un fait technique, pas une ambiguïté musicale.
/// - Sinon : majorité (≥ 2 sur 3 par défaut) sur le même nom d'accord parmi
///   les dernières fenêtres, avec confiance suffisante, pour confirmer un
///   accord affiché.
/// - Sans majorité : l'accord précédemment affiché est tenu pendant
///   [holdFrames] fenêtres avant de basculer sur l'état indéterminé.
class ChordSmoother {
  ChordSmoother({
    this.windowSize = AudioConstants.chordSmootherWindowCount,
    this.holdFrames = AudioConstants.chordHoldFramesOnIndetermination,
    this.minConfidence = AudioConstants.chordMinConfidence,
  });

  final int windowSize;
  final int holdFrames;
  final double minConfidence;

  final List<ChordResult> _window = [];
  SmoothedChord? _lastDetected;
  int _indecisionStreak = 0;

  /// Traite un nouveau `ChordResult` brut et retourne l'état à afficher.
  SmoothedChord push(ChordResult raw) {
    if (raw.chordName == ChordResult.silent.chordName) {
      _window.clear();
      _lastDetected = null;
      _indecisionStreak = 0;
      return SmoothedChord(kind: SmoothedChordKind.silent, result: raw);
    }

    _window.add(raw);
    if (_window.length > windowSize) _window.removeAt(0);

    final majority = _majorityChord();
    if (majority != null) {
      _indecisionStreak = 0;
      final display = SmoothedChord(
        kind: SmoothedChordKind.detected,
        result: majority,
      );
      _lastDetected = display;
      return display;
    }

    final held = _lastDetected;
    if (held != null && _indecisionStreak < holdFrames) {
      _indecisionStreak++;
      return held;
    }
    _indecisionStreak++;
    _lastDetected = null;
    return SmoothedChord(kind: SmoothedChordKind.indeterminate, result: raw);
  }

  /// Accord majoritaire (≥ moitié de [windowSize]) parmi les résultats de
  /// confiance suffisante dans la fenêtre glissante, ou `null` si aucun
  /// nom ne l'emporte.
  ChordResult? _majorityChord() {
    final counts = <String, int>{};
    for (final r in _window) {
      if (r.confidence < minConfidence) continue;
      counts[r.chordName] = (counts[r.chordName] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    final best = counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    final needed = (windowSize / 2).ceil();
    if (best.value < needed) return null;

    return _window.lastWhere((r) => r.chordName == best.key);
  }
}
