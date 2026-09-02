# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce
fichier.

Le format s'appuie sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et ce projet adhère au [Semantic Versioning](https://semver.org/lang/fr/)
(`MAJEUR.MINEUR.CORRECTIF+numéroDeBuild`).

## [Non publié]

### Ajouté
- **Sélecteur de profil d'accordage sur l'écran Tuner** — les deux boutons
  "Standard"/"Guitar" étaient des reliquats de la maquette UI d'origine
  (`onTap: () {}`, jamais raccordés) : un profil créé dans Presets n'avait
  aucun moyen d'être appliqué au Tuner. Remplacés par
  `TuningPresetSelector` : bottom sheet listant "Standard" + tous les
  profils sauvegardés (`TuningProfileRepository.watchAll()`), coche visuelle
  sur le profil actif. `TuningConfiguration` gagne un champ `presetId`
  (`null` = accordage standard) pour savoir quel profil est actif.
  `TunerBloc._onConfigChanged` passe désormais par
  `AudioRepository.updateConfig()` au lieu de relancer l'Isolate/le micro
  (`_subscribeToRepo()`) — changer de preset ou revenir au mode standard ne
  coupe plus l'écoute en cours.
- **US3 — Détection d'accords (étapes 1-6/6, cf.
  `docs/STRATEGIE_DETECTION_ACCORDS.md`)** : reconnaissance d'accords en
  temps réel (polyphonie continue) utilisable de bout en bout dans
  l'application — micro réel → FFT → chromagramme → matching → lissage →
  affichage. Seuls le diagramme de doigté guitare et les annonces
  vocales `Semantics` restent différés (étape 7).
  - `ChordQuality` (`domain/enums`) : 4 qualités reconnues (majeur, mineur,
    7, maj7) avec leurs intervalles.
  - `ChordTemplateLibrary` (`data/workers`) : génération programmatique des
    48 templates d'accords (12 racines × 4 qualités) et matching par
    similitude cosinus.
  - `SpectralPeakExtractor` (`data/workers`) : FFT temps réel via `fftea`
    (fenêtrage de Hann), filtrage de bande [70 Hz, 3000 Hz] et exclusion du
    bin DC avant le peak-picking, détection de maxima locaux affinés par
    interpolation parabolique.
  - `ChromagramBuilder` (`data/workers`) : repliement des pics en vecteur
    chroma 12D (convention MIDI `C=0`) avec compression logarithmique,
    pour éviter qu'une note jouée avec beaucoup d'attaque n'écrase les
    autres degrés de l'accord.
  - `NoteFrequencyConverter.chromaticScale` exposée publiquement pour être
    réutilisée par le moteur d'accords, plutôt que de dupliquer une 3e
    table de noms de notes.
  - Nouvelle dépendance `fftea` (`^1.5.0+1`).
  - `chord_isolate_worker.dart` (`data/workers`) : point d'entrée Isolate du
    pipeline complet (cast PCM → RMS → fenêtrage → FFT → chromagramme →
    matching), avec `ChordWindowAccumulator` pour obtenir un recouvrement de
    50 % (fenêtre FFT 4096 à partir de 2 hops de 2048) sans modifier
    `RecordMicrophoneDataSource`. Constantes `chord*` ajoutées à
    `AudioConstants` (tailles FFT/hop, seuils de silence et de confiance,
    paramètres du futur lissage anti-scintillement).
  - `ChordRepository` (`domain/repositories`) et `ChordRepositoryImpl`
    (`data/repositories`) : expose `streamChord()` côté Domain, miroir
    d'`AudioRepositoryImpl` avec sa propre `MicrophoneDataSource` et son
    propre Isolate (aucune mutualisation avec le Tuner).
  - `ChordSmoother` (`presentation/screens/chords/bloc`) : segmentation par
    événement (onset) — voir le correctif ci-dessous, qui a remplacé le
    design initial en fenêtre glissante continue avant toute publication.
  - `ChordDetectorBloc` : miroir de `TunerBloc`, avec la gestion du cycle
    de vie applicatif et la sérialisation Start/Stop (équivalents BUG-02 /
    BUG-03) branchées dès ce commit plutôt qu'ajoutées après coup.
  - `ChordsScreen` (onglet « Chords ») : remplace le placeholder, branché
    dans `MainShell` avec le même mécanisme `isActive` que le Tuner.
    `ChordNameDisplay` distingue visuellement 3 états (accord confirmé,
    indéterminé, silence) ; `ChromaBarWidget` visualise les 12 degrés du
    chromagramme avec mise en évidence des notes actives.

### Corrigé
- **US3 — Contamination harmonique et flottement/disparition de l'accord
  affiché**, constatés lors d'un premier test sur guitare réelle (cf. §11
  de `docs/STRATEGIE_DETECTION_ACCORDS.md`) :
  - Les accords majeurs classiques ressortaient en "7"/"maj7", les accords
    mineurs étaient mal reconnus — causé par la série d'harmoniques d'une
    note réelle (5e harmonique ≈ tierce majeure, 7e harmonique ≈ 7e
    mineure) amplifiée par une compression `γ=10` jamais calibrée sur du
    son réel. Corrigé par 3 leviers combinés : `SpectralPeakExtractor` ne
    garde plus que les `chordMaxPeaks` (9) pics les plus puissants,
    `chordCompressionGamma` abaissé à `1.0`, et un rasoir d'Occam musical
    dans `ChordTemplateLibrary.match()` (`chordComplexityMargin = 0.08`) :
    un template à 4 notes ne détrône sa triade parente que par un écart de
    score net.
  - Le nom affiché flottait pendant l'attaque d'un strum (transitoire bruyant
    peu fiable) puis disparaissait dès que le volume décroissait sous le
    seuil de silence, alors que la note résonnait encore — causé par un
    lissage en fenêtre glissante continue, inadapté à un accord de guitare
    qui est un événement discret (attaque → sustain → decay → silence), pas
    un flux continu. `ChordSmoother` entièrement réécrit en segmentation
    par événement (onset) : 2 frames d'attaque ignorées, vote majoritaire
    cumulé sur l'événement, 3 frames silencieuses consécutives pour clore
    (un simple creux ne suffit pas), et l'accord résolu reste affiché
    jusqu'au prochain onset (timeout de sécurité à ~5 s de silence total).
- **US3 — Accords à 7e mal détectés (F/Fmaj7 flottant sur un strum tenu)**,
  régression constatée après le correctif ci-dessus (cf. §13 de
  `docs/STRATEGIE_DETECTION_ACCORDS.md`). Cause : le rasoir d'Occam
  tranchait frame par frame dans `ChordTemplateLibrary.match()` — sur un
  strum long, certaines frames franchissaient `chordComplexityMargin`,
  d'autres non, selon la fluctuation naturelle de l'énergie de la 7e ; le
  vote se scindait entre deux noms distincts au sein du même événement.
  `ChordTemplateLibrary.match()` redevient un plus-proche-voisin cosinus
  simple. `ChordTemplate`/`ChordResult` gagnent un champ `familyName`
  (racine + majeur/mineur, sans 7e — "C"/"C7"/"Cmaj7" partagent la même
  famille). `ChordSmoother` vote désormais par confiance cumulée sur une
  fenêtre glissante de `chordVoteWindowSize` (6) frames, regroupée par
  famille : la triade de base l'emporte par défaut, une variante à 7e ne
  la détrône que si son écart moyen dépasse `chordComplexityMargin`
  **et** qu'elle est soutenue par au moins la moitié des frames de la
  fenêtre — un pic isolé ne suffit plus.
- **`RecordMicrophoneDataSource` — crash "Bad state: Stream has already
  been listened to" au 2e cycle start/stop** (remonté par Crashlytics,
  `com.example.harmonix_tune.staging`). `_controller` était un champ
  `final`, créé une seule fois à la construction ; `dispose()` le fermait
  sans jamais le recréer. Or `AudioRepositoryImpl`/`ChordRepositoryImpl`
  réutilisent la même instance de `RecordMicrophoneDataSource` sur toute la
  durée de vie de l'écran (pause/reprise de l'app, changement d'onglet
  répété) — un Stream Dart à abonnement unique ne pouvant être écouté
  qu'une seule fois dans sa vie, le 2e `stream().listen()` plantait
  systématiquement. `AudioRecorder` (paquet `record`) était déjà conçu pour
  être réutilisé après `dispose()` (recréation interne de sa session
  native) — seul notre `StreamController` ne l'était pas. `_controller`
  recréé désormais à chaque appel de `stream()`. Ce crash coupait
  silencieusement le flux micro vers l'Isolate (déjà démarré et accroché) :
  plus aucune détection n'arrivait ensuite, ce qui pouvait donner
  l'impression trompeuse d'un accord "figé" à l'écran.

### Modifié
- CI : l'upload de couverture vers Codecov est désormais ignoré pour les
  pull requests ouvertes par Dependabot — `CODECOV_TOKEN` n'est pas transmis
  aux workflows déclenchés par Dependabot, ce qui faisait systématiquement
  échouer cette étape sur les PRs de mise à jour de dépendances.

## [1.2.0] - 2026-07-21

### Ajouté
- Environnements `dev` / `staging` / `prod` (flavors Android), points
  d'entrée Dart dédiés (`main_dev.dart`, `main_staging.dart`,
  `main_prod.dart`) et `applicationId` distincts par environnement.
- Pipeline de déploiement continu `deploy_beta` : build automatique de
  l'APK release (flavor `staging`) et publication sur Firebase App
  Distribution à chaque push sur `develop` ayant passé la porte de
  qualité (`quality_gate`).

### Corrigé
- **BUG-02** — perte de la détection audio après une mise en arrière-plan
  de l'application puis un retour au premier plan (seul un redémarrage
  complet rétablissait l'écoute). Cause : le flag d'état interne utilisé
  pour décider de relancer l'écoute était écrasé avant d'être testé
  (`tuner_bloc.dart`).
- **BUG-03** — le microphone restait actif en arrière-plan lors de la
  navigation vers un onglet autre que Tuner, du fait du montage permanent
  des écrans par `IndexedStack` (`main_shell.dart`, `tuner_screen.dart`).
- **BUG-01** — le mode Intelli-Tuner ne s'activait jamais automatiquement
  en mode manuel sur un signal à faible confiance : le filtrage de
  confiance appliqué dans l'isolate audio empêchait la condition
  d'auto-activation du BLoC de s'exécuter (`audio_isolate_worker.dart`).

### Tests
- Ajout de tests `bloc_test` couvrant le cycle de vie de l'application
  (arrêt manuel puis pause, permission révoquée pendant la pause, pause
  pendant le mode debug).
- Ajout de tests widget sur la gestion de visibilité d'onglet (montage
  initial vs. transitions `isActive`).
- Extraction et test unitaire dédié de la fonction pure
  `shouldForwardPitch`.

## [1.1.0] - 2026-07-20

### Ajouté
- Intégration de Firebase Crashlytics et Firebase Performance
  (supervision des crashs et des performances applicatives).
- Intégration de Codecov : publication automatique de la couverture de
  tests à chaque exécution de la CI.

### Corrigé
- Alignement du workflow CI sur la branche `master` (au lieu de `main`).

## [1.0.0] - 2026-07-20

### Ajouté
- Accordeur monophonique fonctionnel : pipeline audio réel (microphone
  → Isolate → algorithme YIN), remplaçant le flux mocké de la phase UI
  initiale.
- Gestion des profils d'accordage (onglet Presets, persistance Hive).
- Mise en place de l'intégration continue (GitHub Actions) : formatage,
  analyse statique stricte, exécution des tests unitaires.

[Non publié]: https://github.com/MinaelTrumacher/harmonixTune/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/MinaelTrumacher/harmonixTune/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/MinaelTrumacher/harmonixTune/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/MinaelTrumacher/harmonixTune/releases/tag/v1.0.0
