import 'dart:math';

import '../constants/audio_constants.dart';

// Utilitaire pur (aucune dépendance Flutter) : convertit une note scientifique
// ("E2", "G#3") en fréquence Hz, tempérament égal, selon la convention MIDI
// où l'octave scientifique change de valeur à chaque "C" (C4 = MIDI 60).
abstract final class NoteFrequencyConverter {
  static final RegExp _pattern = RegExp(r'^([A-Ga-g])(#?)(-?\d+)$');

  // Convention MIDI standard C=0 — réutilisée telle quelle pour indexer le
  // chromagramme (détection d'accords) afin d'éviter une 2e table dupliquée.
  static const List<String> chromaticScale = [
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

  static final Map<String, int> _semitoneIndex = {
    for (int i = 0; i < chromaticScale.length; i++) chromaticScale[i]: i,
  };

  // Retourne null si `note` n'est pas au format "<Lettre>[#]<octave>"
  // (ex: octave manquante, lettre hors A-G) — c'est au validateur métier
  // d'interpréter ce null comme un rejet de format, pas à ce convertisseur.
  static double? toFrequencyHz(
    String note, {
    double referenceA4Hz = AudioConstants.referenceA4Hz,
  }) {
    final match = _pattern.firstMatch(note.trim());
    if (match == null) return null;

    final letter = match.group(1)!.toUpperCase();
    final sharp = match.group(2) == '#';
    final octave = int.parse(match.group(3)!);
    final semitoneIndex = _semitoneIndex[sharp ? '$letter#' : letter];
    if (semitoneIndex == null) return null;

    final midi = (octave + 1) * 12 + semitoneIndex;
    return referenceA4Hz * pow(2, (midi - 69) / 12);
  }
}
