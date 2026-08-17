# harmonixTune — Documentation technique de réalisation

> Décrit **comment** l'application a été construite : architecture, choix
> techniques, structure du code, qualité. Complémentaire de
> `DOC_UTILISATION.md` (côté utilisateur final) et `DOC_DEPLOIEMENT.md` (côté
> mise en production/exploitation).

---

## 1. Présentation

**harmonixTune** est un accordeur d'instrument à cordes (guitare, basse,
ukulélé) sous Flutter, ciblant Android et iOS. Positionnement produit : une
application premium sans publicité, avec détection de fréquence en temps réel
robuste au bruit ambiant (cf. `harmonixTune_project_response_ideas.md` pour le
cadrage projet complet — parties prenantes, SWOT, périmètre MVP).

| | |
|---|---|
| Framework | Flutter (Dart) — cross-plateforme Android/iOS/desktop/web |
| Gestion d'état | `flutter_bloc` (BLoC pattern) |
| Persistance locale | Hive (NoSQL embarqué) |
| Backend/télémétrie | Firebase (Crashlytics, Performance) |
| Traitement audio | Isolate Dart dédié + algorithme YIN (détection de hauteur monophonique) |

## 2. Architecture générale

Clean Architecture à 3 couches, règle stricte de dépendance à sens unique :

```
presentation/  →  domain/  ←  data/
  (UI, BLoC)      (entités,     (implémentations concrètes,
                   interfaces)   sources de données, Isolate)
```

- **`domain/`** : aucun import Flutter — entités pures (`PitchResult`,
  `TuningConfiguration`, `TuningProfile`), interfaces de repository
  (`AudioRepository`, `TuningProfileRepository`), validateurs métier
  (`TuningProfileValidator`). Testable sans dépendance externe.
- **`data/`** : implémentations concrètes des interfaces `domain/` — accès
  microphone (`RecordMicrophoneDataSource`), pipeline audio dans un Isolate
  (`AudioIsolateWorker`, `YinDetector`, `IirBandpassFilter`), persistance Hive
  (`TuningProfileRepositoryImpl`).
- **`presentation/`** : écrans + BLoC. Chaque écran reçoit ses dépendances
  par constructeur (`TunerBloc(audioRepository)`,
  `PresetsScreen(repository: ...)`) — pas de service locator ni de singleton
  global, ce qui rend chaque composant testable en isolation.

Détail du flux audio de bout en bout (microphone → Isolate → UI) :
voir `ARCHITECTURE_FLUX.md`. Détail des choix d'implémentation phase par
phase (pourquoi telle dépendance, tel pattern) : voir `DEV_STRATEGY.md` et
`DEVLOG.md`.

## 3. Structure du projet

```
lib/
├── main.dart, main_dev.dart, main_staging.dart, main_prod.dart
├── bootstrap.dart              ← init partagée (Hive, Firebase, Crashlytics)
├── core/
│   ├── config/flavor.dart      ← Flavor dev/staging/prod
│   ├── constants/audio_constants.dart
│   └── utils/note_frequency_converter.dart
├── domain/
│   ├── entities/                (PitchResult, TuningConfiguration, TuningProfile, ChordResult)
│   ├── enums/                   (TunerState, InstrumentType, SweeteningStrategy)
│   ├── exceptions/               (AudioPermissionException, InvalidTuningProfileException)
│   ├── repositories/              (interfaces AudioRepository, TuningProfileRepository)
│   └── validators/               (TuningProfileValidator)
├── data/
│   ├── datasources/               (RecordMicrophoneDataSource, AudioBufferAccumulator)
│   ├── models/                    (TuningProfileModel — persistance Hive)
│   ├── repositories/               (implémentations concrètes)
│   └── workers/                   (AudioIsolateWorker, YinDetector, IirBandpassFilter)
└── presentation/
    ├── theme/                      (AppColors, AppTextStyles, AppTheme)
    ├── navigation/main_shell.dart   (3 onglets : Tuner / Presets / Chords)
    └── screens/
        ├── tuner/                   (BLoC + widgets CustomPainter animés)
        ├── presets/                 (BLoC + éditeur de profil)
        └── chords/                  (stub — cf. §5)

test/  — miroir de la structure lib/, 226 tests (cf. §6)
```

## 4. Choix techniques justifiés

| Choix | Alternative écartée | Justification |
|---|---|---|
| Flutter | Natif Swift/Kotlin séparés, React Native | Une seule base de code, UI fluide 60/120 Hz (moteur Impeller/Skia adapté aux animations d'accordeur), logique métier partagée et testable. Voir comparatif complet dans `harmonixTune_project_response_ideas.md` §Phase 4. |
| BLoC (`flutter_bloc`) | Provider, Riverpod, setState | Séparation stricte événements/état, testable sans widget (`bloc_test`), standard de l'industrie Flutter. |
| Isolate Dart pour l'audio | Traitement sur le thread UI | Le calcul YIN + filtre IIR à 44.1 kHz bloquerait le thread UI (jank). L'Isolate déporte le calcul, communication via `SendPort`/`ReceivePort`. |
| Algorithme YIN | FFT/autocorrélation simple | Meilleure précision sur fondamentale monophonique avec bruit, standard pour les accordeurs. Fallback autocorrélation prévu en cas d'échec YIN. |
| Hive | SQLite (`sqflite`), `shared_preferences` | Pas de schéma SQL nécessaire pour de simples profils d'accordage ; API asynchrone simple, performant pour de petits volumes, pas de dépendance native lourde. |
| Firebase (Crashlytics/Performance) | Sentry | Intégration Flutter la plus rapide à mettre en place (cf. arbitrage documenté dans `MONITORING_SETUP.md`). |
| `record_linux` figé via `dependency_overrides` | Montée majeure de `record` (5→7) | Incident de version incompatible dans le paquet `record` (cf. `FLAVORS_SETUP.md §4`) ; correctif minimal plutôt qu'une migration majeure risquée sur le pipeline audio, non testée. |

## 5. Modules fonctionnels

### 5.1 Tuner (complet)

Pipeline : microphone (`record` plugin) → conversion PCM Int16→double
normalisé → Isolate (`AudioIsolateWorker`) → `YinDetector` (+ `IirBandpassFilter`
optionnel, activé par l'Intelli-Tuner) → `PitchResult` renvoyé au `TunerBloc`
→ UI (aiguille, barre de cents, nom de note).

Fonctionnalités : détection AUTO (n'importe quelle corde) ou manuelle (corde
ciblée), Intelli-Tuner (filtre passe-bande auto-activé sur confiance faible en
mode manuel), gestion du cycle de vie (coupure micro hors premier plan ou hors
onglet Tuner — cf. `STRATEGIE_CORRECTION_BOGUES.md` BUG-02/BUG-03), gestion
des permissions (refus simple/définitif).

### 5.2 Presets (complet)

CRUD de profils d'accordage (nom, type d'instrument, liste de cordes)
persistés localement via Hive, avec validation métier (3 à 8 cordes, nom
unique 3-50 caractères, fréquences dans la plage détectable 43-1200 Hz —
`TuningProfileValidator`).

### 5.3 Chords (conception terminée, non codé)

Détection d'accords polyphonique (STFT + chromagramme 12 dimensions +
similitude cosinus à un dictionnaire de templates), dans un Isolate dédié.
Spécification technique complète et arbitrages actés dans `UC_03_strategy.md`
(statut "Validé, prêt pour codage") — reste à implémenter.

## 6. Qualité et tests

| Indicateur | Valeur |
|---|---|
| Tests automatisés | 226 (unitaires domain/data, `bloc_test` sur les BLoC, widgets via `flutter_test` + mocktail) |
| Couverture de lignes | 88.6% (`flutter test --coverage`, publié sur Codecov en CI) |
| Analyse statique | `flutter analyze --fatal-warnings --fatal-infos` — 0 issue |

Harnais détaillé (stratégie de mock, limites connues — ex. `record_microphone_data_source.dart`
et le code généré Hive difficiles à tester unitairement) : voir l'historique
de construction du harnais dans les échanges de conception et les fichiers
`test/` eux-mêmes, qui documentent chaque cas limite en commentaire.

## 7. Documents de référence

| Document | Contenu |
|---|---|
| `ARCHITECTURE_FLUX.md` | Diagramme de séquence détaillé du flux audio |
| `DEV_STRATEGY.md` / `DEVLOG.md` | Phases de construction de l'UI et décisions techniques associées |
| `UC_01_strategy.md` / `UC_02_strategy.md` / `UC_03_strategy.md` | Spécifications techniques par cas d'utilisation (Tuner, Presets, Chords) |
| `AUDIT_PRE_MERGE.md` / `AUDIT_POST_FIX.md` | Revues de code historiques (Phases 1-4) |
| `PLAN_CORRECTION_BOGUES.md` / `STRATEGIE_CORRECTION_BOGUES.md` | Anomalies détectées en recette et correctifs appliqués |

---

*harmonixTune — DOC_REALISATION v1.0*
