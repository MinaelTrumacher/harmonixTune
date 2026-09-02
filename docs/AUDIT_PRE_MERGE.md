# harmonixTune — Audit pré-merge

> Audit de la branche `main` avant merge sur `develop`.
> Périmètre : Phases 1–4 (28 fichiers, 1 358 lignes ajoutées).
> Méthode : 7 angles d'analyse (correctness × 3, cleanup × 3, altitude × 1) + vérification indépendante par agent.

---

## Statut global

| Catégorie | Findings | Bloquants merge |
|---|---|---|
| 🔴 Bloquant | 1 | **1 — NE PAS MERGER** |
| 🟠 Sérieux | 3 | 0 (à corriger avant Phase 9) |
| 🟡 Modéré | 3 | 0 (à corriger avant Phase 9) |
| ⚪ Mineur | 3 | 0 (suivi en backlog) |

---

## Findings détaillés

---

### F-01 — 🔴 BLOQUANT · `string_selector_widget.dart:27`

**Sélecteur de cordes définitivement désactivé**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/widgets/string_selector_widget.dart` |
| Ligne | 27 |
| Résolu | ☐ |

**Analyse :**
L'app démarre avec `_config.targetString = null` (AUTO mode).
`isAuto = (selected == null)` est donc `true` dès le lancement.
`onTap: isAuto ? null : ...` désactive tous les `GestureDetector`.
Le seul moyen de rendre `isAuto = false` serait qu'une corde soit sélectionnée,
mais c'est impossible puisque les taps sont désactivés.
Boucle infinie : le sélecteur de cordes est mort pour toute la session.

**Code fautif :**
```dart
onTap: isAuto
    ? null   // ← bloque les taps quand targetString == null (état initial permanent)
    : () => context.read<TunerBloc>().add(StringSelected(isSelected ? null : note)),
```

**Fix :**
```dart
// Toujours autoriser le tap — l'action toggle entre AUTO et manuel
onTap: () => context.read<TunerBloc>().add(
  StringSelected(isSelected ? null : note),
),
// Retirer le bloc `onTap: isAuto ? null : ...` — l'opacité 0.4 suffit à indiquer l'état AUTO
```

---

### F-02 — 🟠 Sérieux · `tuner_needle_widget.dart:~57`

**Couleur d'aiguille figée sur la transition inTune → silence**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/widgets/tuner_needle_widget.dart` |
| Ligne | 57–70 |
| Résolu | ☐ |

**Analyse :**
Quand l'aiguille est centrée (note parfaitement juste, `_displayAngle ≈ 0`) et que l'utilisateur
arrête de jouer, le BLoC émet `TunerInitial`.
Le `BlocListener` écrit `_tunerState = TunerState.silent` **sans appeler `setState`**.
Le Ticker vérifie `|0 - 0| = 0 < 0.0001` → skip du `setState`.
`build()` n'est jamais rappelé → le painter ne reçoit jamais la nouvelle couleur.
L'aiguille reste verte (`AppColors.inTune`) indéfiniment.

**Scénario de reproduction :**
1. Jouer une note parfaitement en accord → aiguille verte, centrée.
2. Arrêter de jouer.
3. L'aiguille reste verte alors qu'elle devrait passer à `AppColors.textDisabled`.

**Fix :**
```dart
listener: (_, state) {
  final newState = state is TunerListening
      ? state.pitch.state
      : TunerState.silent;
  final newTarget = state is TunerListening
      ? (state.pitch.centsDeviation.clamp(-50.0, 50.0) / 50.0) * (pi / 2)
      : 0.0;
  // Forcer setState si l'état fonctionnel change, même si l'angle ne bouge pas
  if (_tunerState != newState) {
    setState(() {
      _tunerState = newState;
      _targetAngle = newTarget;
    });
  } else {
    _targetAngle = newTarget;
  }
},
```

---

### F-03 — 🟠 Sérieux · `tuner_bloc.dart:46`

**Erreurs de stream silencieusement avalées**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/bloc/tuner_bloc.dart` |
| Ligne | 46 |
| Résolu | ☐ |

**Analyse :**
`_mockStream().listen(...)` n'a pas de callback `onError`.
En Phase 9, une erreur du plugin audio (permission refusée, interruption système,
device déconnecté) annule silencieusement la subscription Dart.
Le BLoC ne l'apprend jamais, ne change pas d'état, et l'UI reste figée sur le
dernier `TunerListening` sans aucun feedback.

**Code fautif :**
```dart
_subscription = _mockStream().listen(
  (s) => add(PitchReceived(s.frequencyHz, s.centsDeviation)),
  // ← pas de onError
);
```

**Fix :**
```dart
_subscription = _mockStream().listen(
  (s) => add(PitchReceived(s.frequencyHz, s.centsDeviation)),
  onError: (Object error, StackTrace stack) {
    add(const StopTuner()); // remet l'UI en état propre
  },
  cancelOnError: true,
);
```

---

### F-04 — 🟠 Sérieux · `tuner_bloc.dart:137`

**`AudioConstants.minConfidence` jamais vérifié**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/bloc/tuner_bloc.dart` + `lib/core/constants/audio_constants.dart` |
| Ligne | 137 (helper `_pitchFromCents`) |
| Résolu | ☐ |

**Analyse :**
`AudioConstants.minConfidence = 0.85` est défini mais jamais lu.
`_pitchFromCents` hardcode `confidence: 0.95` et ne filtre pas les détections
à faible confiance. En Phase 9, les résultats bruités de l'algorithme YIN
(bruit ambiant, transitoires d'attaque, harmoniques parasites) seront émis
comme des `TunerListening` valides → l'aiguille réagira à des faux positifs
dans des environnements de répétition.

**Impact différé :** inactif en Phase 4 (mock), critique en Phase 9.

**Fix (à appliquer en Phase 9 quand l'Isolate envoie une vraie confidence) :**
```dart
PitchResult? _pitchFromResult(double hz, double cents, double confidence) {
  if (confidence < AudioConstants.minConfidence) return null; // → TunerState.silent
  // ... reste identique
}
```

---

### F-05 — 🟡 Modéré · `tuner_state.dart:27`

**`Equatable.props` avec des types sans `==`**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/bloc/tuner_state.dart` |
| Ligne | 27 |
| Résolu | ☐ |

**Analyse :**
`TunerListening.props = [pitch, config, intelliTunerEnabled]`.
`PitchResult` et `TuningConfiguration` n'implémentent ni `==` ni `hashCode`.
L'égalité est par référence (identité d'objet). Chaque `PitchReceived` crée
un nouveau `PitchResult` → les états ne sont jamais "égaux" du point de vue
d'`Equatable` → `BlocBuilder` reconstruit tous les widgets descendants à ~60 Hz,
même quand aucune valeur visible ne change (note et cents identiques).

**Conséquence :** `NoteDisplayWidget` et `StringSelectorWidget` se rebuildent
à la fréquence audio, pas seulement quand la note change.

**Fix :**
Option A (minimal) : ajouter `buildWhen` sur les `BlocBuilder` non-critiques :
```dart
BlocBuilder<TunerBloc, TunerDisplayState>(
  buildWhen: (prev, next) {
    if (prev is! TunerListening || next is! TunerListening) return true;
    return prev.pitch.noteName != next.pitch.noteName ||
           prev.pitch.octave != next.pitch.octave;
  },
  builder: (_, state) { ... },
)
```

Option B (complet) : implémenter `==` / `hashCode` sur `PitchResult` et `TuningConfiguration`.

---

### F-06 — 🟡 Modéré · `cents_bar_widget.dart`

**Shader Skia recréé à chaque frame**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/widgets/cents_bar_widget.dart` |
| Ligne | ~105 |
| Résolu | ☐ |

**Analyse :**
`LinearGradient(...).createShader(rect)` est appelé dans `paint()` à chaque repaint.
`createShader()` alloue un objet natif Skia côté C++ (ref-counted `sk_sp<SkShader>`).
Le gradient est une constante (ses couleurs ne changent jamais). La rect ne change
que si le widget est redimensionné (pratiquement jamais après le premier layout).

**Fix :**
```dart
// Dans le painter :
Shader? _cachedShader;
double _cachedWidth = -1;

@override
void paint(Canvas canvas, Size size) {
  if (size.width != _cachedWidth) {
    _cachedShader = const LinearGradient(
      colors: [/* ... */],
    ).createShader(Rect.fromLTWH(ballRadius, barY - 2, size.width - 2 * ballRadius, 4));
    _cachedWidth = size.width;
  }
  // Utiliser _cachedShader
}
```

---

### F-07 — 🟡 Modéré · `tuner_needle_widget.dart`

**~9 `Paint()` alloués par repaint**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/widgets/tuner_needle_widget.dart` |
| Ligne | multiples |
| Résolu | ☐ |

**Analyse :**
`_drawArc` (×1), `_drawInTuneZone` (×1), `_drawGraduations` (×2), `_drawNeedle` (×2),
`_drawPivot` (×3) : 9 objets `Paint()` créés localement à chaque appel de `paint()`.
Les paints dont les propriétés sont des constantes peuvent être élevés en champs
`late final` du painter, éliminant l'allocation.

**Fix (paints constants à cacher) :**
```dart
class _NeedlePainter extends CustomPainter {
  // Paints statiques — jamais recalculés
  static final _arcPaint = Paint()
    ..color = AppColors.surfaceHigh
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  static final _inTunePaint = Paint()
    ..color = AppColors.inTune.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;

  static final _majorGradPaint = Paint()
    ..color = AppColors.textSecondary
    ..strokeWidth = 1.5;

  static final _minorGradPaint = Paint()
    ..color = AppColors.textDisabled
    ..strokeWidth = 1;
  // (pivotPaints idem)

  // Paints dynamiques — dépendent de needleColor (peu fréquent)
  late Paint _needlePaint;
  late Paint _tipPaint;
  // ... recalculés uniquement quand needleColor change
}
```

---

### F-08 — ⚪ Mineur · `tuning_configuration.dart:6`

**Literal `440.0` duplique `AudioConstants.referenceA4Hz`**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/domain/entities/tuning_configuration.dart` |
| Ligne | 6 |
| Résolu | ☐ |

**Fix :**
```dart
// Avant :
this.referencePitchHz = 440.0,

// Après :
this.referencePitchHz = AudioConstants.referenceA4Hz,
```
Note : `tuning_configuration.dart` est dans le Domain (pure Dart). Importer
`audio_constants.dart` depuis `core/` reste dans la même couche — acceptable.

---

### F-09 — ⚪ Mineur · `tuner_bloc.dart` + `domain/enums/tuner_state.dart`

**`nearTuneThresholdCents` défini mais jamais utilisé**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/core/constants/audio_constants.dart` · `lib/domain/enums/tuner_state.dart` |
| Résolu | ☐ |

**Analyse :**
`AudioConstants.nearTuneThresholdCents = 5.0` est une constante orpheline.
`_pitchFromCents` saute directement de `inTune` (≤2 cents) à `tooLow/tooHigh`
sans zone intermédiaire ambre. Si la zone ambre (±5 cents) du design doit exister,
il faut une valeur `TunerState.nearTune` dans l'enum **et** un cas dans `_pitchFromCents`.

**Options :**
- Supprimer la constante si la zone ambre est abandonnée.
- Ajouter `TunerState.nearTune` + l'implémentation dans `_pitchFromCents`.

---

### F-10 — ⚪ Mineur · `tuning_configuration.dart:33`

**Cast `Object? → String?` non sécurisé dans `copyWith`**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/domain/entities/tuning_configuration.dart` |
| Ligne | 33 |
| Résolu | ☐ |

**Code fautif :**
```dart
targetString: targetString == _sentinel
    ? this.targetString
    : targetString as String?,  // ← CastError si appelant passe un non-String
```

**Fix :**
Remplacer le sentinel par un booléen explicite :
```dart
TuningConfiguration copyWith({
  double? referencePitchHz,
  SweeteningStrategy? sweetening,
  List<String>? stringNotes,
  String? targetString,
  bool clearTargetString = false,  // ← intent explicite, type-safe
  InstrumentType? instrumentType,
}) {
  return TuningConfiguration(
    targetString: clearTargetString ? null : (targetString ?? this.targetString),
    // ...
  );
}
```

---

## Plan de résolution

### Avant merge (aujourd'hui)

| # | Finding | Fichier | Effort estimé |
|---|---|---|---|
| F-01 | Sélecteur cordes désactivé | `string_selector_widget.dart` | 5 min | ✅ |
| F-02 | Couleur aiguille figée | `tuner_needle_widget.dart` | 10 min | ✅ |
| F-03 | `onError` manquant | `tuner_bloc.dart` | 5 min | ✅ |

### Avant Phase 9 (avant branchement audio réel)

| # | Finding | Fichier | Effort estimé |
|---|---|---|---|
| F-04 | `minConfidence` non vérifié | `tuner_bloc.dart` | 15 min |
| F-05 | `Equatable.props` cassé | `tuner_state.dart` + entités | 30 min |
| F-08 | Literal `440.0` | `tuning_configuration.dart` | 5 min |
| F-10 | Cast non sécurisé | `tuning_configuration.dart` | 10 min |

### Backlog (optimisation)

| # | Finding | Fichier | Effort estimé |
|---|---|---|---|
| F-06 | Shader recréé | `cents_bar_widget.dart` | 20 min |
| F-07 | Paint() allocs | `tuner_needle_widget.dart` | 20 min |
| F-09 | `nearTuneThresholdCents` orphelin | `audio_constants.dart` + enum | 15 min |

---

*harmonixTune — Audit pré-merge v1.0 — Phases 1–4*
*Prochaine action : corriger F-01, F-02, F-03 puis re-valider avec `flutter analyze`*
