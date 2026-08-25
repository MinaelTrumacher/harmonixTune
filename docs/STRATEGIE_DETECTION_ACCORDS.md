# harmonixTune — Stratégie de développement : détection d'accords (US3)

**Statut :** Cadrage validé. Étapes 1 à 6 implémentées et testées — la
détection d'accords est utilisable de bout en bout dans l'app (micro réel →
FFT → chromagramme → matching → lissage → UI), diagramme de doigté et
`Semantics` vocaux restant seuls différés à l'étape 7. 303 tests projet, 0
échec, `flutter analyze` propre. Dépendance `fftea: ^1.5.0+1` ajoutée à
`pubspec.yaml`.
**Référence :** `DEV_STRATEGY.md` (Phase 6 initiale — UI mock uniquement),
`ARCHITECTURE_FLUX.md`, pipeline Tuner réel (`lib/data/workers/audio_isolate_worker.dart`,
`lib/data/repositories/audio_repository_impl.dart`, `lib/presentation/screens/tuner/`).

> `DEV_STRATEGY.md` s'arrêtait à un `ChordsScreen` avec chromagramme mocké
> (Phase 6). Ce document couvre la suite : le vrai pipeline DSP (FFT →
> chromagramme → reconnaissance d'accord) et son branchement à l'UI, sur le
> modèle de ce qui a été fait pour le Tuner (Phases 7–9 du document
> d'origine), en respectant l'architecture Clean déjà en place.

---

## 1. Objectif (US3)

Reconnaître en continu l'accord joué (ex. Do Majeur, La mineur 7) à partir du
flux audio polyphonique, via FFT (`fftea`, N=4096 @ 44 100 Hz, fenêtrage de
Hann), extraction de pics spectraux, chromagramme 12 dimensions (convention
MIDI `C=0`), et comparaison par similitude cosinus à 48 templates d'accords
(Majeur, mineur, 7, Maj7). Cas limites à couvrir : silence (RMS), bruit
parasite (bin DC, bande passante 70–3000 Hz), indécision (hold + état
« Indéterminé »).

---

## 2. Constat de l'existant (vérifié dans le code actuel)

- `domain/entities/chord_result.dart` et l'état `ChordResult.silent` existent
  déjà. `presentation/screens/chords/chords_screen.dart` est un placeholder
  statique (« Chords — Phase 6 »).
- `AudioConstants.bufferSize = 2048` échantillons — **c'est exactement le hop
  size (50 % overlap) nécessaire pour une FFT 4096**. `RecordMicrophoneDataSource`
  livre déjà des buffers PCM de 2048 échantillons toutes les ~46 ms, sans
  modification.
- Chaque écran audio (Tuner) instancie son propre
  `AudioRepositoryImpl(RecordMicrophoneDataSource())` à l'activation et se
  coupe via `isActive` / `didUpdateWidget` (correctif BUG-03). Le worker
  Isolate est une fonction top-level pure (`audioIsolateEntryPoint`)
  déléguant à des classes DSP pures et testables isolément
  (`YinDetector`, `IirBandpassFilter`).
- `NoteFrequencyConverter` (`core/utils/`) encode déjà la convention MIDI
  `C=0`, mais sa table de 12 noms est privée — un 2ᵉ tableau de noms existe
  déjà en dur dans `audio_isolate_worker.dart` (convention `A=0`, différente).

---

## 3. Décisions d'architecture arbitrées

### 3.1 Mutualisation du micro → isolation, pas mutualisation

Tuner et Chords ne sont jamais actifs simultanément (un seul onglet visible
dans l'`IndexedStack`, chacun avec son `isActive`). `ChordsScreen` instancie
donc son propre `ChordRepositoryImpl(RecordMicrophoneDataSource())`
indépendant — exactement comme `TunerScreen`. `RecordMicrophoneDataSource`
reste **inchangée** : pas besoin de lui faire diffuser deux tailles de chunk.

### 3.2 Fenêtrage / recouvrement 50 % → géré dans l'Isolate Chords

Le flux livre déjà des hops de 2048 échantillons (~46 ms). Le worker Chords
maintient en interne un ring buffer de 4096 échantillons (concaténation des
2 derniers hops reçus) et relance une FFT à **chaque nouveau hop** :
recouvrement 50 % obtenu sans toucher à l'accumulateur partagé, rafraîchissement
~46 ms conforme au besoin exprimé dans le cadrage. Premier hop = frame froide
(buffer à moitié rempli) → pas d'émission tant que le ring buffer n'est pas
plein, même logique que le YIN qui ignore un buffer insuffisant.

### 3.3 Constantes → étendre `AudioConstants`, pas de fichier séparé

`AudioConstants` mélange déjà générique (`sampleRate`) et spécifique Tuner
(`stringFrequencies`). Ajouter les constantes Chords dedans (préfixe `chord*`)
garde un seul endroit de vérité :

```dart
static const int chordFftSize = 4096;
static const int chordHopSize = 2048; // = AudioConstants.bufferSize
static const double chordSilenceRmsThreshold = 0.01; // à calibrer
static const double chordMinFreqHz = 70.0;
static const double chordMaxFreqHz = 3000.0;
static const double chordMinConfidence = 0.65; // à calibrer
static const int chordSmootherWindowCount = 3;
static const int chordHoldFramesOnIndetermination = 2;
```

### 3.4 Réutilisation de la convention de notes

Exposer publiquement la liste ordonnée `C=0` déjà encodée dans
`NoteFrequencyConverter` plutôt que dupliquer un 3ᵉ tableau de 12 noms. Le
chromagramme et le nommage des accords s'appuient sur cette liste unique.

### 3.5 Dictionnaire des 48 templates → généré, pas codé en dur

```dart
enum ChordQuality { major, minor, dominant7, major7 }
// intervalles : [0,4,7] / [0,3,7] / [0,4,7,10] / [0,4,7,11]
```

Les 48 vecteurs (12 racines × 4 qualités) sont générés par rotation à
l'initialisation — évite 48 littéraux figés et les erreurs de recopie.

### 3.6 Lissage anti-scintillement → couche Présentation, pas DSP

`ChordSmoother` (fenêtres glissantes + hold sur indétermination) vit à côté
de `ChordDetectorBloc`, symétrique au choix déjà fait pour le Tuner où le
BLoC ne fait aucun DSP. L'Isolate reste une fonction de traitement par frame,
sans état temporel autre que le ring buffer.

### 3.7 Cycle de vie (BUG-03) branché dès le premier commit

`ChordDetectorBloc` reprend le `WidgetsBindingObserver` de `TunerBloc`
(pause/resume) et `ChordsScreen` reprend le paramètre `isActive` de
`TunerScreen` dès la V1 — pas de dette corrective à porter plus tard, contrairement
au Tuner où BUG-03 a dû être corrigé après coup (cf. `STRATEGIE_CORRECTION_BOGUES.md`).

---

## 4. Arborescence des nouveaux fichiers

```
lib/
├── core/
│   └── utils/
│       └── note_frequency_converter.dart   ← exposer la liste C=0 (existant, à étendre)
├── domain/
│   ├── entities/
│   │   └── chord_result.dart               ← existe déjà
│   ├── enums/
│   │   └── chord_quality.dart               ← major | minor | dominant7 | major7
│   └── repositories/
│       └── chord_repository.dart           ← interface, streamChord()
├── data/
│   ├── workers/
│   │   ├── spectral_peak_extractor.dart    ← FFT fftea + Hann + pics + interp. parabolique
│   │   ├── chromagram_builder.dart         ← pics → vecteur 12D, compression log/sqrt
│   │   ├── chord_template_library.dart     ← génération des 48 templates + cosine similarity
│   │   └── chord_isolate_worker.dart       ← entrée Isolate, ring buffer 4096, RMS gate
│   └── repositories/
│       └── chord_repository_impl.dart      ← spawn isolate, miroir audio_repository_impl.dart
└── presentation/
    └── screens/
        └── chords/
            ├── chords_screen.dart          ← remplace le placeholder Phase 6
            ├── bloc/
            │   ├── chord_detector_bloc.dart
            │   ├── chord_event.dart
            │   ├── chord_state.dart
            │   └── chord_smoother.dart
            └── widgets/
                ├── chord_name_display.dart
                └── chroma_bar_widget.dart   ← CustomPainter (déjà prévu dans DEV_STRATEGY.md)
```

Dépendance à ajouter dans `pubspec.yaml` : `fftea` (dernière version stable).

---

## 5. Détails techniques par composant

### 5.1 `chord_isolate_worker.dart` (miroir de `audio_isolate_worker.dart`)

Messages : `InitWorkerMessage` / `AudioBufferMessage` (réutilisables tels
quels) / `KillWorkerMessage` en entrée, `ChordDetectedMessage(ChordResult)`
en sortie. Pipeline par hop reçu :

1. Cast `Int16List` → `Float64List` normalisé (identique au Tuner).
2. Décalage du ring buffer 4096 (`[hop N-1, hop N]`) — pas d'émission avant
   qu'il soit plein.
3. RMS sur le hop courant → si `< chordSilenceRmsThreshold`, court-circuite
   et émet `ChordResult.silent` (pas de FFT gaspillée).
4. Fenêtrage de Hann + FFT 4096 via `fftea`.
5. Filtrage bande 70–3000 Hz **et** exclusion du bin `0` (DC) **avant** le
   peak-picking — pas seulement en post-filtrage, sinon un artefact basse
   fréquence peut fausser l'interpolation parabolique du premier pic valide.
6. `SpectralPeakExtractor` : maxima locaux + interpolation parabolique.
7. `ChromagramBuilder` : repliement des pics sur 12 bins, compression
   `log(1 + γ·|X(f)|)` (évite qu'une seule note d'attaque forte n'écrase
   tierce/quinte).
8. `ChordTemplateLibrary.match(chroma)` : cosine similarity contre les 48
   templates → `(chordName, confidence)`.
9. Émission `ChordResult(chordName, chromaVector, confidence, activeNoteIndices)`.

### 5.2 `chord_smoother.dart` (Présentation)

Fenêtre glissante de 3 résultats (`chordSmootherWindowCount`). Règle de
sortie :
- Majorité (≥2/3) sur le même `chordName` avec confiance suffisante → accord
  affiché mis à jour.
- Sinon → conserve le dernier accord affiché pendant
  `chordHoldFramesOnIndetermination` fenêtres avant de basculer sur
  « Indéterminé ».
- Un accord à 2 notes (quinte / power chord) ne matchera aucun des 48
  templates avec une similarité suffisante → doit basculer proprement sur
  « Indéterminé » plutôt que remonter un faux positif à faible confiance.

### 5.3 Accessibilité

`Semantics` avec annonce vocale déclenchée **uniquement** sur une transition
d'accord validée par `ChordSmoother` (pas à chaque frame brute) — évite le
spam d'annonces à ~22 Hz de rafraîchissement brut.

---

## 6. Séquencement de dev proposé

| Étape | Contenu | Testable sans device | Livrable |
|---|---|---|---|
| 1 | `chord_quality.dart`, `chord_template_library.dart` | ✅ (vecteurs synthétiques) | 48 templates générés, matching cosine unitairement validé |
| 2 | `spectral_peak_extractor.dart`, `chromagram_builder.dart` | ✅ (sinusoïdes sommées) | Chromagramme correct sur accords synthétiques connus |
| 3 | `chord_isolate_worker.dart` | ✅ (spawn réel, comme `audio_isolate_worker_test.dart`) | Isolate complet, silence/DC/bande passante couverts |
| 4 | `chord_repository_impl.dart` | ✅ (source/isolate mockés) | Stream `ChordResult` exposé côté Domain |
| 5 | `chord_detector_bloc.dart` + `chord_smoother.dart` | ✅ (`bloc_test`) | Lissage anti-scintillement + cycle de vie testés |
| 6 | `chords_screen.dart` + widgets | UI manuelle | Nom d'accord + confiance + notes actives affichés, `isActive` branché |
| 7 (différée) | Diagramme de doigté guitare, `Semantics` vocaux | UI manuelle | Itération suivante, non bloquante pour la valeur fonctionnelle de l'US3 |

---

## 7. Plan de tests (miroir de la suite existante)

```
test/
├── domain/enums/chord_quality_test.dart
├── data/workers/
│   ├── chord_template_library_test.dart   ← 48 templates, cosine similarity
│   ├── spectral_peak_extractor_test.dart  ← pics + interpolation parabolique
│   ├── chromagram_builder_test.dart       ← compression log/sqrt, repliement 12D
│   └── chord_isolate_worker_test.dart     ← silence RMS, bande 70-3000Hz, bin DC
├── data/repositories/chord_repository_impl_test.dart
└── presentation/screens/chords/
    ├── bloc/chord_detector_bloc_test.dart
    ├── bloc/chord_smoother_test.dart
    └── chords_screen_test.dart
```

---

## 8. Risques et points de vigilance

- **Coût CPU** : FFT 4096 toutes les ~46 ms dans l'Isolate — budget plus
  serré que le YIN actuel (buffer 2048, pas de FFT). À profiler tôt sur
  device bas de gamme, avant d'investir dans le lissage UI.
- **Calibration des seuils** (`chordSilenceRmsThreshold`, `chordMinConfidence`)
  : valeurs de départ arbitraires, à ajuster à l'oreille/au device comme
  `AudioConstants.minConfidence` l'a été pour le Tuner.
- **Ambiguïté musicale** : accords partiels (2 notes), harmoniques fortes
  d'une seule corde jouée seule → risque de faux positifs si le seuil de
  confiance du template matching est trop permissif.

---

## 9. Arbitrages validés (points ouverts §9 initial)

1. **Extension d'`AudioConstants`** (§3.3) plutôt qu'un fichier séparé
   `ChordConstants` — **validé**. Point d'entrée unique pour toute la config
   audio ; le préfixe `chord*` suffit à la lisibilité.
2. **Report du diagramme de doigté guitare et des `Semantics` vocaux** à
   l'étape 7 — **validé**. Approche incrémentale : la valeur métier repose
   d'abord sur la précision de la détection et la stabilité du
   `ChordSmoother` ; l'enrichissement IHM vient consolider ensuite.
3. **Valeurs initiales de calibration** — **validées** :
   `chordSilenceRmsThreshold = 0.01`, `chordMinConfidence = 0.65`.
   Justification du seuil de confiance : le score cosinus entre un accord et
   son relatif majeur/mineur (ex. `C` vs `Am`, 2 degrés communs sur 3) vaut
   naturellement `2/3 ≈ 0.667` — vérifié par
   `chord_template_library_test.dart` (`cosine(C, Am) ≈ 0.667`). Un seuil de
   `0.65` place la barre juste sous cette ambiguïté structurelle, à affiner
   en conditions réelles.

---

## 10. Avancement

| Étape | Statut | Détail |
|---|---|---|
| 1 — `chord_quality.dart` + `chord_template_library.dart` | ✅ Fait | 48 templates générés par rotation, matching cosine, `NoteFrequencyConverter.chromaticScale` exposé publiquement (évite une 3e table de noms dupliquée). Tests : génération (unicité, 12 racines × 4 qualités), match sur accords purs (C, Am), silence (vecteur nul → confiance 0.0 sans exception), ambiguïté relatif majeur/mineur. |
| 2 — `spectral_peak_extractor.dart` + `chromagram_builder.dart` | ✅ Fait | Dépendance `fftea` ajoutée. `SpectralPeakExtractor` : fenêtrage `Window.hanning`, FFT via `FFT(fftSize).realFft().discardConjugates().magnitudes()`, filtrage bande [minFreqHz, maxFreqHz] + bin DC exclu **avant** peak-picking, interpolation parabolique (même formule/garde que `YinDetector._findTauStar`). Aucun couplage à `AudioConstants` (constructeur à paramètres explicites, comme `YinDetector`/`IirBandpassFilter`) — le câblage aux constantes app se fera à l'étape 3 (Isolate). `ChromagramBuilder` : repliement MIDI `C=0`, compression `log(1+γ·magnitude)` (γ=10). Tests : silence, repliement multi-octave, bande passante (50 Hz et 4000 Hz exclus), interpolation (440 Hz retrouvé à ±3 Hz sur une résolution de bin brute de ~10,77 Hz), compression log vérifiée par un ratio concret (note faible à 0,01 en linéaire remonte à >0,3 après compression). |
| 3 — `chord_isolate_worker.dart` | ✅ Fait | Constantes `chord*` ajoutées à `AudioConstants` (§3.3, valeurs validées). `ChordWindowAccumulator` : classe dédiée au recouvrement 50 % (concatène les 2 derniers hops), `@visibleForTesting`, testée indépendamment (chauffe, fenêtre, glissement). Pipeline `_processHop` : cast Int16→Float64, RMS **toujours** calculée et l'accumulateur **toujours** alimenté (même en silence, pour ne pas désynchroniser le recouvrement), court-circuit silence avant la vérification de chauffe, puis FFT → chromagramme → matching. Pas de seuillage `chordMinConfidence` dans l'Isolate : le nom/la confiance bruts sont toujours émis, la décision « Indéterminé » revient au `ChordSmoother` (étape 5), conformément à §5.2. Test d'intégration bout-en-bout (spawn réel de l'Isolate) : accord Do majeur reconnu sur 2 hops consécutifs à phase continue. |
| 4 — `chord_repository_impl.dart` | ✅ Fait | `ChordRepository` (interface) : `streamChord({referenceA4Hz})` + `stop()` — pas d'`updateConfig` (aucun besoin de reconfiguration à chaud identifié pour l'instant, contrairement au Tuner). `ChordRepositoryImpl` est un miroir quasi exact d'`AudioRepositoryImpl` (même gestion `StreamController` lazy `onListen`/`onCancel`, mêmes garde-fous de cycle de vie Isolate/DataSource) — confirme concrètement la décision d'isolation §3.1 : sa propre `MicrophoneDataSource`, son propre Isolate, aucun couplage au Tuner. Tests mockant `MicrophoneDataSource` (comme `audio_repository_impl_test.dart`) : accord Do majeur détecté sur 2 chunks PCM, `ChordResult.silent` émis pour un chunk silencieux, permission refusée propagée, cycle de vie `stop()`. |
| 5 — `chord_detector_bloc.dart` + `chord_smoother.dart` | ✅ Fait | `ChordSmoother` : silence = état immédiat sans hold (fait technique, pas une ambiguïté musicale) et réinitialise le dernier accord confirmé ; sinon majorité ≥2/3 sur la fenêtre glissante avec confiance suffisante, sinon hold de l'accord précédemment confirmé pendant `chordHoldFramesOnIndetermination` fenêtres avant bascule sur indéterminé. `ChordDetectorBloc` : miroir de `TunerBloc` — `WidgetsBindingObserver` (BUG-02) et sérialisation Start/Stop via `_guarded` (BUG-03) branchés dès ce commit, pas ajoutés après coup comme ça l'a été pour le Tuner. Tests : séquence complète du smoother (indétermination → majorité → hold → bascule), confiance sous seuil, réinitialisation par le silence ; BLoC testé avec `bloc_test`/`mocktail` sur le même plan que `tuner_bloc_test.dart` (cycle de vie, sérialisation, permission, confirmation d'accord sur 2 réceptions). |
| 6 — `chords_screen.dart` + widgets | ✅ Fait | `ChordsScreen` : miroir exact de `TunerScreen` (injection par constructeur, `isActive` branché dans `MainShell`, vue de refus de permission). `ChordNameDisplay` : nom d'accord + confiance pour `detected`, "Indéterminé" pour `indeterminate`, "Jouez un accord" pour `silent` — 3 états visuellement distincts, pas de confusion entre absence de signal et ambiguïté musicale. `ChromaBarWidget` : 12 barres (`CustomPainter`, sans Ticker — la cadence vient déjà du `ChordSmoother`), degrés actifs mis en évidence, labels via `NoteFrequencyConverter.chromaticScale`. Tests : montage initial + transitions `isActive` (miroir `tuner_screen_test.dart`), 3 états de `ChordNameDisplay`, `ChromaBarWidget` sans exception sur accord détecté et sur une séquence de changements d'état. |
| 7 (différée) — doigté guitare, `Semantics` vocaux | Différée | — |
