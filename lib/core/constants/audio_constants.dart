abstract final class AudioConstants {
  static const int sampleRate = 44100;
  static const int bufferSize = 2048;
  static const double inTuneThresholdCents = 2.0;
  static const double nearTuneThresholdCents = 5.0;
  static const double minConfidence = 0.85;
  static const double referenceA4Hz = 440.0;

  // Fréquences théoriques des cordes (accord standard, A4 = 440 Hz).
  // Utilisées par l'Isolate worker pour centrer le filtre IIR.
  // Limite basse : E2 = 82.41 Hz → τ ≈ 535, dans la plage τ_max = N/2 = 1024.
  static const Map<String, double> stringFrequencies = {
    'E2': 82.41,
    'A2': 110.00,
    'D3': 146.83,
    'G3': 196.00,
    'B3': 246.94,
    'E4': 329.63,
  };

  // minDetectableHz = sampleRate / (bufferSize / 2) ≈ 43 Hz.
  // En dessous de cette limite, τ dépasse N/2 et l'algorithme YIN ne peut
  // pas fonctionner avec un buffer de 2048 samples.
  static const double minDetectableHz = sampleRate / (bufferSize / 2);

  // ── Détection d'accords (US3) — cf. docs/STRATEGIE_DETECTION_ACCORDS.md ──

  // Taille FFT (résolution) et hop (cadence de rafraîchissement). hopSize
  // == bufferSize : le flux micro livre déjà des chunks de cette taille,
  // donc l'Isolate accords obtient un recouvrement de 50 % en concaténant
  // 2 hops consécutifs, sans toucher à RecordMicrophoneDataSource.
  static const int chordFftSize = 4096;
  static const int chordHopSize = bufferSize;

  static const double chordSilenceRmsThreshold = 0.01;
  static const double chordMinFreqHz = 70.0;
  static const double chordMaxFreqHz = 3000.0;

  // Score de similitude cosinus en dessous duquel un accord n'est pas
  // considéré comme fiable. Calibré juste sous 2/3 ≈ 0,667, le score
  // structurel entre un accord et son relatif majeur/mineur (ex. C/Am) —
  // cf. chord_template_library_test.dart.
  static const double chordMinConfidence = 0.65;

  // Fraction du degré chromatique dominant (vecteur normalisé [0,1]) à
  // partir de laquelle un degré est considéré comme une note active.
  static const double chordActiveNoteThreshold = 0.5;

  // Filtrage des pics avant construction du chromagramme : au-delà de N
  // pics, l'essentiel est du résidu harmonique plutôt que de nouvelles
  // fondamentales — une guitare à 6 cordes ne produit que 6 fondamentales
  // simultanées.
  static const int chordMaxPeaks = 9;

  // Compression log(1 + γ·magnitude) du ChromagramBuilder. γ=10 (valeur
  // initiale, jamais validée sur du son réel avant recette manuelle)
  // amplifiait excessivement les harmoniques faibles — 5e harmonique
  // ≈ tierce majeure 2 octaves plus haut, 7e harmonique ≈ 7e mineure — au
  // point de rivaliser avec les vraies fondamentales de l'accord : des
  // accords majeurs classés "7"/"maj7", des accords mineurs mal reconnus
  // (tierce majeure fantôme). Abaissé après diagnostic sur guitare réelle.
  static const double chordCompressionGamma = 1.0;

  // Marge minimale (en score cosinus) qu'un template à 4 notes (7, maj7)
  // doit dépasser son "parent" à 3 notes (la triade majeure dont il est le
  // sur-ensemble d'intervalles) pour le détrôner dans ChordTemplateLibrary.
  // Rasoir d'Occam musical : à score presque égal, un template plus riche
  // accroche plus facilement le résidu harmonique — la triade la plus
  // simple doit l'emporter sauf écart net.
  static const double chordComplexityMargin = 0.08;

  // Segmentation par événement (onset) du ChordSmoother — un strum de
  // guitare est un événement discret (attaque → sustain → decay →
  // silence), pas un flux continu à lisser frame par frame.
  // ~93 ms : le transitoire d'attaque du médiator retombe généralement
  // en moins de 100 ms ; ces frames ne participent pas au vote.
  static const int chordAttackFramesToSkip = 2;
  // ~140 ms de silence consécutif avant de clore l'événement — évite de
  // fermer prématurément sur un creux vibratoire de la corde (battement
  // harmonique) plutôt qu'une vraie fin de note.
  static const int chordEventCloseSilentFrames = 3;
  // ~5 s de silence total avant de réinitialiser doucement l'affichage
  // vers l'état silencieux (filet de sécurité, pas une limite normale —
  // l'accord résolu reste sinon affiché jusqu'au prochain onset).
  static const int chordSilenceTimeoutFrames = (5 * sampleRate) ~/ chordHopSize;
}
