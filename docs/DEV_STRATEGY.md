# harmonixTune — Stratégie de développement

> Document soumis à validation avant tout code.
> Référence : `UI_DESIGN.md` + `ARCHITECTURE_FLUX.md`

---

## 1. Dépendances à ajouter

```yaml
dependencies:
  flutter_bloc: ^8.1.6      # BLoC pattern
  equatable: ^2.0.5         # Equality sur les states/events BLoC
  google_fonts: ^6.2.1      # Police Inter
  gap: ^3.0.1               # Gap(16) au lieu de SizedBox(height: 16)
```

> **Pas de `go_router`** : la navigation est un `IndexedStack` + `BottomNavigationBar`.
> Trois onglets fixes, zéro deep-link nécessaire en V1. go_router serait du sur-engineering.

---

## 2. Structure complète des fichiers

```
lib/
│
├── main.dart
│
├── core/
│   └── constants/
│       └── audio_constants.dart      ← sampleRate, bufferSize, thresholds
│
├── domain/                           ← Pure Dart, zéro import Flutter
│   ├── entities/
│   │   ├── pitch_result.dart
│   │   ├── chord_result.dart
│   │   └── tuning_configuration.dart
│   ├── enums/
│   │   ├── tuner_state.dart          ← silent | tooLow | inTune | tooHigh
│   │   ├── sweetening_strategy.dart  ← none | railsback | guitarCompensated
│   │   └── instrument_type.dart      ← guitar | bass | ukulele | custom
│   └── repositories/
│       └── audio_repository.dart     ← Interface abstraite uniquement
│
├── data/                             ← Implémentations concrètes
│   ├── repositories/
│   │   └── audio_repository_impl.dart
│   ├── datasources/
│   │   └── microphone_data_source.dart
│   ├── isolate/
│   │   ├── audio_isolate_config.dart ← Config passée à l'Isolate au spawn
│   │   └── audio_isolate_worker.dart ← Entry point de l'Isolate
│   └── strategies/
│       ├── pitch_detection_strategy.dart       ← Interface Strategy
│       ├── yin_pitch_strategy.dart             ← Implémentation YIN
│       └── autocorrelation_pitch_strategy.dart ← Implémentation fallback
│
└── presentation/
    ├── app.dart                      ← MaterialApp + ThemeData
    ├── theme/
    │   ├── app_colors.dart
    │   ├── app_text_styles.dart
    │   └── app_theme.dart
    ├── navigation/
    │   └── main_shell.dart           ← IndexedStack + BottomNavigationBar
    ├── screens/
    │   ├── tuner/
    │   │   ├── tuner_screen.dart
    │   │   ├── bloc/
    │   │   │   ├── tuner_bloc.dart
    │   │   │   ├── tuner_event.dart
    │   │   │   └── tuner_state.dart
    │   │   └── widgets/
    │   │       ├── tuner_needle_widget.dart   ← CustomPainter + Ticker
    │   │       ├── cents_bar_widget.dart       ← CustomPainter + Ticker
    │   │       ├── note_display_widget.dart
    │   │       ├── string_selector_widget.dart
    │   │       ├── intelli_tuner_toggle.dart
    │   │       └── tuning_preset_chip.dart
    │   ├── presets/
    │   │   ├── presets_screen.dart
    │   │   ├── bloc/
    │   │   │   ├── presets_bloc.dart
    │   │   │   ├── presets_event.dart
    │   │   │   └── presets_state.dart
    │   │   └── widgets/
    │   │       ├── preset_card.dart
    │   │       └── preset_editor_sheet.dart
    │   └── chords/
    │       ├── chords_screen.dart
    │       ├── bloc/
    │       │   ├── chords_bloc.dart
    │       │   ├── chords_event.dart
    │       │   └── chords_state.dart
    │       └── widgets/
    │           ├── chord_name_display.dart
    │           ├── chroma_bar_widget.dart     ← CustomPainter
    │           └── chord_logger_widget.dart
    └── shared/
        ├── app_header.dart
        └── settings_sheet.dart
```

---

## 3. Phases de développement

### Phase 1 — Foundation (Projet & Thème)

**Fichiers créés :**
- `pubspec.yaml` : ajout des 4 dépendances
- `lib/core/constants/audio_constants.dart`
- `lib/presentation/theme/app_colors.dart`
- `lib/presentation/theme/app_text_styles.dart`
- `lib/presentation/theme/app_theme.dart`
- `lib/presentation/app.dart`
- `lib/main.dart` (nettoyé)

**Résultat attendu :** app qui démarre avec fond noir `#0D0D14` et police Inter.

---

### Phase 2 — Domain (Entités & Interfaces)

> Le Domain est créé **avant** la Présentation car les BLoC states référencent les entités.
> Aucune implémentation ici — seulement des classes et interfaces pures.

**Fichiers créés :**
- `lib/domain/enums/tuner_state.dart`
- `lib/domain/enums/sweetening_strategy.dart`
- `lib/domain/enums/instrument_type.dart`
- `lib/domain/entities/pitch_result.dart`
- `lib/domain/entities/tuning_configuration.dart`
- `lib/domain/entities/chord_result.dart`
- `lib/domain/repositories/audio_repository.dart` (interface abstraite)

**Contenu de `pitch_result.dart` :**
```dart
class PitchResult {
  final double frequencyHz;
  final String noteName;
  final int octave;
  final double centsDeviation; // -50.0 à +50.0
  final double confidence;     // 0.0 à 1.0
  final TunerState state;
}
```

**Contenu de `audio_repository.dart` (interface) :**
```dart
abstract interface class AudioRepository {
  Stream<PitchResult> streamPitch(TuningConfiguration config);
  Future<void> updateConfig(TuningConfiguration config);
  Future<void> stop();
}
```

**Résultat attendu :** couche Domain compilable, aucun import `flutter`.

---

### Phase 3 — Navigation & Shell

**Fichiers créés :**
- `lib/presentation/navigation/main_shell.dart`

**Mécanique :**
```dart
// IndexedStack : garde les 3 screens en mémoire, pas de rebuild au changement d'onglet
IndexedStack(
  index: _currentIndex,
  children: [TunerScreen(), PresetsScreen(), ChordsScreen()],
)
```

**Résultat attendu :** navigation entre 3 onglets fonctionnelle avec placeholders.

---

### Phase 4 — TunerScreen (UI + BLoC mock)

C'est la phase la plus longue. Le BLoC utilise un **mock stream** à la place du vrai audio.

**Stratégie mock :**
```dart
// Dans TunerBloc, pendant la phase UI :
// Un Stream.periodic simule le flux audio avec des valeurs sinusoïdales
Stream<PitchResult>.periodic(
  const Duration(milliseconds: 16), // ~60 Hz
  (i) => PitchResult(
    frequencyHz: 329.6 + sin(i * 0.1) * 10,
    noteName: 'E',
    octave: 4,
    centsDeviation: sin(i * 0.05) * 30,
    confidence: 0.95,
    state: TunerState.inTune,
  ),
)
```

Un **`Slider` de debug** (visible seulement en mode debug) permettra de forcer
la valeur de `centsDeviation` de -50 à +50 pour tester tous les états visuels.

**Fichiers créés (dans l'ordre) :**

1. `bloc/tuner_event.dart` + `bloc/tuner_state.dart`
2. `bloc/tuner_bloc.dart` (avec mock stream)
3. `widgets/tuner_needle_widget.dart` ← **le plus complexe** (CustomPainter + Ticker)
4. `widgets/cents_bar_widget.dart` (CustomPainter + Ticker partagé)
5. `widgets/note_display_widget.dart`
6. `widgets/string_selector_widget.dart` (désactivé visuellement si mode AUTO actif)
7. `widgets/intelli_tuner_toggle.dart`
8. `widgets/tuning_preset_chip.dart`
9. `tuner_screen.dart` (assemble tous les widgets)
10. `shared/app_header.dart`

**Points techniques clés de cette phase :**

- `TunerNeedleWidget` et `CentsBarWidget` sont deux `StatefulWidget` **indépendants**,
  chacun avec son propre `SingleTickerProviderStateMixin` et son propre `Ticker` local.
- Raison : si un seul Ticker parent pilote les deux widgets, passer la valeur
  interpolée en descendant via `setState` invalide l'arbre et annule le bénéfice
  du `RepaintBoundary`. Chaque widget doit gérer son propre vsync dans son propre
  `RepaintBoundary`.
- Les deux widgets lisent la même valeur **cible** (`targetCents`) depuis le `TunerBloc`
  via `BlocBuilder`, mais interpole indépendamment à chaque frame.
- Le `BlocBuilder` met à jour `_targetAngle` / `_targetCents` sans `setState` —
  c'est le `Ticker` qui déclenche le repaint.

```dart
// TunerNeedleWidget — son propre Ticker
class _TunerNeedleState extends State<TunerNeedleWidget>
    with SingleTickerProviderStateMixin { ... }

// CentsBarWidget — son propre Ticker indépendant
class _CentsBarState extends State<CentsBarWidget>
    with SingleTickerProviderStateMixin { ... }

// Chacun écoute le BLoC pour la valeur cible, interpole seul
BlocListener<TunerBloc, TunerDisplayState>(
  listener: (context, state) => _targetCents = state.centsDeviation,
  child: RepaintBoundary(child: CustomPaint(painter: _needlePainter)),
)
```

**Résultat attendu :** TunerScreen navigable avec aiguille animée, slider de debug,
états visuels (vert/bleu/rouge) fonctionnels — zéro audio réel.

---

### Phase 5 — PresetsScreen (UI + BLoC mock)

BLoC avec une **liste de presets hardcodée** (pas de BDD encore).

**Fichiers créés :**
- `bloc/presets_event.dart` + `bloc/presets_state.dart`
- `bloc/presets_bloc.dart` (liste statique)
- `widgets/preset_card.dart` (avec Dismissible pour swipe-to-delete)
- `widgets/preset_editor_sheet.dart` (formulaire, pas de persistance)
- `presets_screen.dart`

**Résultat attendu :** liste de presets navigable, bottom sheet d'édition ouvrable.

---

### Phase 6 — ChordsScreen (UI + BLoC mock)

BLoC avec un **vecteur chroma mock** animé.

**Fichiers créés :**
- `bloc/chords_event.dart` + `bloc/chords_state.dart`
- `bloc/chords_bloc.dart` (vecteur chroma simulé)
- `widgets/chord_name_display.dart`
- `widgets/chroma_bar_widget.dart` (CustomPainter)
- `widgets/chord_logger_widget.dart`
- `chords_screen.dart`
- `shared/settings_sheet.dart`

**Résultat attendu :** prototype UI complet navigable, toutes les animations visibles.

---

### Phase 7 — Data Layer : Strategy Pattern (sans micro)

> Implémenté et testé **sans** le micro — les stratégies prennent un `List<double>`
> en entrée et sont testables avec des données synthétiques en `flutter_test`.

**Fichiers créés :**
- `data/strategies/pitch_detection_strategy.dart` (interface)
- `data/strategies/yin_pitch_strategy.dart`
- `data/strategies/autocorrelation_pitch_strategy.dart`

**Interface Strategy :**
```dart
abstract interface class PitchDetectionStrategy {
  PitchResult? detect({
    required List<double> samples,  // PCM normalisé [-1.0, 1.0]
    required int sampleRate,
    required TuningConfiguration config,
  });
}
```

**Résultat attendu :** les deux stratégies sont unitairement testables sans device.

---

### Phase 8 — Data Layer : Pipeline Audio

**Fichiers créés :**
- `data/isolate/audio_isolate_config.dart`
- `data/isolate/audio_isolate_worker.dart`
- `data/datasources/microphone_data_source.dart`
- `data/repositories/audio_repository_impl.dart`

**Responsabilité de conversion PCM — dans l'Isolate worker :**

Le plugin d'enregistrement Flutter (ex. `record`) délivre un `Stream<Uint8List>`
— des octets bruts. L'algorithme YIN attend des `List<double>` normalisés entre
-1.0 et 1.0. Cette conversion est la **première opération** de l'Isolate worker,
avant tout calcul :

```dart
// audio_isolate_worker.dart — début du pipeline de traitement
void _processBuffer(Uint8List rawBytes) {
  // Étape 1 : reinterpret cast zero-copie Uint8List → Int16List
  final Int16List samples = rawBytes.buffer.asInt16List();

  // Étape 2 : normalisation Int16 → double [-1.0, 1.0]
  // Int16 va de -32768 à +32767, donc on divise par 32768.0
  final List<double> normalized = List.generate(
    samples.length,
    (i) => samples[i] / 32768.0,
  );

  // Étape 3 : passage à la PitchDetectionStrategy
  final result = _strategy.detect(
    samples: normalized,
    sampleRate: _config.sampleRate,
    config: _config.tuningConfig,
  );

  if (result != null) _replyPort.send(result);
}
```

> Le `.buffer.asInt16List()` est un **reinterpret cast zéro-copie** : aucune allocation
> mémoire supplémentaire. Critique pour ne pas créer de GC pressure dans l'Isolate
> à 50 Hz.

**Résultat attendu :** `AudioRepositoryImpl` implémente `AudioRepository` et expose
un vrai `Stream<PitchResult>` depuis le micro.

---

### Phase 9 — Connexion Domain → Présentation

Remplacement du mock stream par le vrai `AudioRepository` dans le `TunerBloc`.

**Mécanique de re-subscription sur `ConfigChanged` :**

Quand l'utilisateur change de configuration (instrument, preset, sweetening…),
le BLoC ne peut pas simplement appeler `updateConfig` sur un stream ouvert.
Il doit fermer le flux existant et en ouvrir un nouveau :

```dart
class TunerBloc extends Bloc<TunerEvent, TunerDisplayState>
    with WidgetsBindingObserver {

  final AudioRepository _audioRepository;
  StreamSubscription<PitchResult>? _pitchSubscription; // toujours stockée
  TuningConfiguration _currentConfig;

  // Démarrage initial ou re-subscription après changement de config
  Future<void> _subscribe() async {
    // 1. Annuler l'ancien flux avant tout
    await _pitchSubscription?.cancel();
    _pitchSubscription = null;

    // 2. Ouvrir un nouveau flux avec la config courante
    _pitchSubscription = _audioRepository
        .streamPitch(_currentConfig)
        .listen((result) => add(PitchReceived(result)));
  }

  // Handler de l'événement ConfigChanged
  Future<void> _onConfigChanged(
    ConfigChanged event,
    Emitter<TunerDisplayState> emit,
  ) async {
    _currentConfig = event.config;
    await _subscribe(); // cancel + re-subscribe atomique
  }

  // Nettoyage — obligatoire pour éviter les fuites de Stream
  @override
  Future<void> close() async {
    await _pitchSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    return super.close();
  }
}
```

Gestion `AppLifecycleState` dans le `TunerBloc` : `paused` → `_pitchSubscription.cancel()`,
`resumed` → `_subscribe()` — sans fermer le BLoC lui-même.

**Résultat attendu :** app fonctionnelle de bout en bout avec vrai signal micro.

---

## 4. Résumé des phases & livrables

| Phase | Contenu | Livrable |
|---|---|---|
| 1 | Foundation, thème | App noire avec police Inter |
| 2 | Domain : entités, interfaces | Couche Domain compilable |
| 3 | Navigation | 3 onglets fonctionnels |
| 4 | TunerScreen + BLoC mock | Aiguille animée, slider debug |
| 5 | PresetsScreen + BLoC mock | Liste presets, bottom sheet |
| 6 | ChordsScreen + BLoC mock | Chromagramme animé |
| **7** | **Strategy Pattern** | **YIN + Autocorrélation testables** |
| **8** | **Pipeline Audio** | **Vrai flux micro** |
| **9** | **Connexion** | **App complète V1** |

Phases 1–6 = UI cliquable (pas de micro).
Phases 7–9 = mécanique audio (branchement progressif).

---

## 5. Règles de codage respectées tout au long

- `domain/` : zéro `import 'package:flutter'` — pur Dart
- `data/` : connait `domain/`, ignore `presentation/`
- `presentation/` : connait `domain/`, **ne connaît pas** `data/` directement
  → le BLoC reçoit l'`AudioRepository` (interface Domain) par injection
- Chaque BLoC reçoit ses dépendances en constructeur (pas de singleton global)
- Les `CustomPainter` sont tous enveloppés dans `RepaintBoundary`
- Tout élément piloté par le flux audio utilise Lerp + Ticker (pas d'AnimationController à durée fixe)
- Toute souscription à un `Stream` dans un BLoC est stockée dans une variable
  `StreamSubscription?` et annulée dans `close()` — aucune exception
- La re-subscription sur `ConfigChanged` suit le pattern : `cancel()` → update config
  → nouvelle `listen()` — jamais d'update en cours de stream ouvert
- Le mock stream est supprimé en Phase 9, pas commenté — pas de code mort

---

*En attente de validation avant démarrage de la Phase 1.*
