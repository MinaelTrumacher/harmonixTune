# harmonixTune — Audit post-fix

> Audit de la branche `initUI` après correction des 10 findings de `AUDIT_PRE_MERGE.md`.
> Périmètre : 1 438 lignes ajoutées, 29 fichiers.
> Méthode : 7 angles (correctness × 3, cleanup × 3, altitude × 1) + vérification indépendante.

---

## Statut global

| Catégorie | Findings | Bloquants merge |
|---|---|---|
| 🔴 Bloquant | 1 | **1 — NE PAS MERGER** |
| 🟠 Sérieux | 1 | 0 (à corriger avant Phase 9) |
| 🟡 Modéré | 2 | 0 |
| ⚪ Mineur | 5 | 0 |

---

## Régression vs audit précédent

Le fix **F-02** (`TunerNeedleWidget` — couleur figée sur `inTune → silent`) a été correctement
appliqué sur l'aiguille mais **pas reporté sur `CentsBarWidget`** qui souffre du même bug.

---

## Findings détaillés

---

### PF-01 — 🔴 BLOQUANT · `cents_bar_widget.dart:55`

**Régression F-02 : couleur de la bille figée sur la transition `inTune → silent`**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/widgets/cents_bar_widget.dart` |
| Lignes | 55–63 |
| Résolu | ☐ |

**Analyse :**
Le `BlocListener` de `CentsBarWidget` écrit `_tunerState` sans `setState`.
Si la bille est centrée (≈ 0 cents, note parfaitement juste) et que le BLoC émet
`TunerInitial` (utilisateur arrête de jouer), le Ticker vérifie
`|0 - 0 * alpha| < 0.005` → skip. La couleur reste verte indéfiniment.

C'est exactement le bug F-02 corrigé dans `TunerNeedleWidget` (lignes 69–76)
mais qui **n'a pas été reporté sur `CentsBarWidget`**.

**Code fautif :**
```dart
listener: (_, state) {
  if (state is TunerListening) {
    _targetCents = state.pitch.centsDeviation.clamp(-50.0, 50.0);
    _tunerState = state.pitch.state;       // ← pas de setState
  } else {
    _targetCents = 0.0;
    _tunerState = TunerState.silent;       // ← pas de setState
  }
},
```

**Fix — même pattern que le needle :**
```dart
listener: (_, state) {
  final newTunerState =
      state is TunerListening ? state.pitch.state : TunerState.silent;
  final newTarget = state is TunerListening
      ? state.pitch.centsDeviation.clamp(-50.0, 50.0)
      : 0.0;
  if (_tunerState != newTunerState) {
    setState(() {
      _tunerState = newTunerState;
      _targetCents = newTarget;
    });
  } else {
    _targetCents = newTarget;
  }
},
```

---

### PF-02 — 🟠 Sérieux · `tuner_bloc.dart`

**`AppLifecycleState` non implémenté — stream actif en arrière-plan**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/bloc/tuner_bloc.dart` |
| Résolu | ☐ |

**Analyse :**
`WidgetsBindingObserver`, `didChangeAppLifecycleState` et `AppLifecycleState`
sont absents de toute la base de code (présents uniquement dans les `.md`).
Le `Stream.periodic` à 16 ms tourne indéfiniment dès que le BLoC est créé,
même quand l'app passe en arrière-plan.

En Phase 9, cela maintiendra le micro ouvert et l'Isolate actif en tâche de fond
— violation RGPD (micro actif hors session) + consommation batterie continue.

L'`IndexedStack` dans `MainShell` aggrave le problème : le BLoC n'est jamais
`disposed` lors des changements d'onglet, donc c'est le **seul** mécanisme
disponible pour pauser le traitement audio.

Ce comportement est explicitement planifié dans `DEV_STRATEGY.md` (Phase 9)
et `ARCHITECTURE_FLUX.md` mais n'a pas été implémenté.

**Impact différé** : inactif en Phase 4 (mock), critique en Phase 9 (micro réel).

**Fix :**
```dart
class TunerBloc extends Bloc<TunerEvent, TunerDisplayState>
    with WidgetsBindingObserver {

  TunerBloc() : super(const TunerInitial()) {
    WidgetsBinding.instance.addObserver(this);
    // ... on<>() handlers
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _subscription?.cancel();
      _subscription = null;
    }
    if (state == AppLifecycleState.resumed) {
      _subscribe();
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    return super.close();
  }
}
```

---

### PF-03 — 🟡 Modéré · `tuner_bloc.dart:50`

**Race `add()` après `close()` : événement silencieusement perdu**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/bloc/tuner_bloc.dart` |
| Ligne | 50 |
| Résolu | ☐ |

**Analyse :**
`_mockStream().listen((s) => add(...))` n'a pas de garde `isClosed`.
Quand `BlocProvider` dispose le BLoC (navigation), `close()` appelle
`await _subscription?.cancel()`. Mais le timer Dart peut avoir déjà
schedulé un tick pour les 16 ms suivantes avant que `cancel()` resolves.
Le callback `(s) => add(...)` peut s'exécuter après `isClosed = true`.

En flutter_bloc 8.x, `add()` après fermeture **ne lance pas d'exception** —
l'événement est **silencieusement ignoré**. Pas de crash, mais perte d'événement.
Le même risque existe pour `onError: (e, s) => add(const StopTuner())`.

**Fix :**
```dart
_subscription = _mockStream().listen(
  (s) {
    if (!isClosed) add(PitchReceived(s.frequencyHz, s.centsDeviation, confidence: 0.95));
  },
  onError: (Object error, StackTrace stack) {
    if (!isClosed) add(const StopTuner());
  },
  cancelOnError: true,
);
```

---

### PF-04 — 🟡 Modéré · `pitch_result.dart:51`

**`PitchResult.==` sur `double` exact rend l'optimisation `BlocBuilder` inerte**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/domain/entities/pitch_result.dart` |
| Ligne | 51 |
| Résolu | ☐ |

**Analyse :**
Le mock génère `frequencyHz = 329.6 + cents * 0.19` et
`centsDeviation = sin(tick * 0.04) * 35.0`. Deux ticks consécutifs
produisent des `double` différents (même sur une note stable).
`TunerListening.props` contient le `PitchResult` — Equatable délègue
à `PitchResult.==` — la comparaison exacte échoue à chaque tick.
`BlocBuilder` reconstruit donc **inconditionnellement** à 60 Hz,
même quand le texte affiché est identique (ex. la note ne change pas).

En Phase 9 avec du vrai FFT, deux frames d'une note stable ne produiront
jamais des `double` bit-identiques → même comportement.

**Fix :**
```dart
// Comparer avec epsilon sur les doubles — en dessous de la résolution affichée
static const double _centsEpsilon = 0.05; // < toStringAsFixed(1)

@override
bool operator ==(Object other) {
  if (identical(this, other)) return true;
  return other is PitchResult &&
      other.noteName == noteName &&
      other.octave == octave &&
      other.state == state &&
      (other.centsDeviation - centsDeviation).abs() < _centsEpsilon &&
      (other.frequencyHz - frequencyHz).abs() < 0.01;
}
```

---

### PF-05 — ⚪ Mineur · `cents_bar_widget.dart:117`

**Cache du shader : clé incomplète (largeur seule, pas la hauteur)**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/widgets/cents_bar_widget.dart` |
| Ligne | 117 |
| Résolu | ☐ |

**Analyse :**
Le shader est caché sur `barWidth` uniquement. `barY = size.height / 2`
entre aussi dans le `Rect` de `createShader`. Si la hauteur du widget
change (clavier virtuel, layout dynamique), `barY` change mais le shader
reste calculé avec l'ancien `Rect` → gradient décalé verticalement.

En pratique, le widget est dans un `SizedBox(height: 32)` — risque très faible.
Mais la clé de cache est architecturalement incorrecte.

**Fix :**
```dart
if (barWidth != _cachedBarWidth || size.height != _cachedBarHeight) {
  _barShader = const LinearGradient(colors: _gradientColors)
      .createShader(Rect.fromLTWH(barLeft, barY - 2, barWidth, 4));
  _cachedBarWidth = barWidth;
  _cachedBarHeight = size.height;
}
```

---

### PF-06 — ⚪ Mineur · `cents_bar_widget.dart:127`

**`Paint()` alloué à chaque repaint pour envelopper le shader caché**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/widgets/cents_bar_widget.dart` |
| Ligne | 127 |
| Résolu | ☐ |

**Analyse :**
```dart
canvas.drawRRect(
  ...,
  Paint()..shader = _barShader,  // ← nouveau Paint() à chaque frame
);
```

Le shader est correctement caché (`static Shader? _barShader`) mais le `Paint`
qui l'encapsule est créé à nouveau à chaque appel de `paint()`. À 60 Hz :
~60 objets `Paint` court-vivants par seconde pour ce seul draw call.

**Fix :**
```dart
static Paint? _barPaint;
// Dans la section de cache shader :
if (barWidth != _cachedBarWidth) {
  _barShader = ...createShader(...);
  _barPaint = Paint()..shader = _barShader;
  _cachedBarWidth = barWidth;
}
canvas.drawRRect(..., _barPaint!);
```

---

### PF-07 — ⚪ Mineur · `tuner_needle_widget.dart:173`

**22 appels `sin`/`cos` par frame pour des graduations géométriquement constantes**

| Champ | Valeur |
|---|---|
| Statut | **CONFIRMED** |
| Fichier | `lib/presentation/screens/tuner/widgets/tuner_needle_widget.dart` |
| Ligne | 173 |
| Résolu | ☐ |

**Analyse :**
`_drawGraduations()` calcule à chaque `paint()` les 11 angles des graduations
(−50 à +50 cents, pas 10) et leurs `cos`/`sin`, soit **22 appels trig/frame**
à 120 Hz = ~2 640 opérations trigonométriques/seconde pour de la géométrie fixe.
Le rayon `radius` est aussi recalculé depuis `size` à chaque frame même si le
widget n'a pas été redimensionné.

**Fix :**
```dart
// Cache dans le painter — recalculé uniquement si radius change
static double _cachedRadius = -1;
static List<({Offset inner, Offset outer, bool isMajor})> _gradPoints = [];

static void _rebuildGradPoints(double radius, Offset center) {
  _cachedRadius = radius;
  _gradPoints = [
    for (int i = -50; i <= 50; i += 10)
      (
        inner: Offset(center.dx + (radius - (i % 20 == 0 ? 14 : 8)) * cos(...),
                      ...),
        outer: Offset(...),
        isMajor: i % 20 == 0,
      )
  ];
}
```

---

### PF-08 — ⚪ Mineur · `tuner_needle_widget.dart:131`

**`late final` sur les paints dynamiques — piège sémantique de maintenance**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/widgets/tuner_needle_widget.dart` |
| Ligne | 131 |
| Résolu | ☐ |

**Analyse :**
```dart
late final Paint _needleLinePaint = Paint()..color = needleColor...;
late final Paint _needleTipPaint  = Paint()..color = needleColor;
```

`late final` est initialisé une fois par instance au premier accès et **ne peut
plus être modifié**. Le code est correct aujourd'hui car une nouvelle instance de
`_NeedlePainter` est créée à chaque repaint (shouldRepaint retourne true quand
`needleColor` change). Mais si un futur refactoring retire `needleColor` de
`shouldRepaint` ou réutilise l'instance painter, les couleurs resteront figées
silencieusement sans erreur de compilation.

**Fix :**
Remplacer `late final` par des champs ordinaires initialisés dans le constructeur,
ou documenter explicitement le couplage avec `shouldRepaint`.

---

### PF-09 — ⚪ Mineur · `tuner_screen.dart:87`

**Deux `BlocBuilder` indépendants reçoivent chaque émission à 60 Hz**

| Champ | Valeur |
|---|---|
| Statut | **PLAUSIBLE** |
| Fichier | `lib/presentation/screens/tuner/tuner_screen.dart` |
| Ligne | 87 |
| Résolu | ☐ |

**Analyse :**
Le label des cents (ligne 87) et `_DebugCentsSlider` (ligne 136) sont deux
`BlocBuilder` indépendants. Chacun reçoit toutes les émissions du BLoC à ~60 Hz.
Conséquence directe du finding PF-04 : tant que `PitchResult.==` compare des
`double` exacts, les deux builders se reconstruisent à chaque tick même si le
texte affiché n'a pas changé.

**Fix :** corriger PF-04 en premier, puis envisager un `BlocSelector` sur
`centsDeviation.toStringAsFixed(1)` pour le label (rebuild uniquement quand
la valeur affichée change, ~10× moins souvent).

---

## Plan de résolution

### Avant merge (immédiat)

| # | Finding | Fichier | Effort |
|---|---|---|---|
| PF-01 | Régression F-02 CentsBarWidget | `cents_bar_widget.dart` | 10 min |

### Avant Phase 9 (avant branchement micro réel)

| # | Finding | Fichier | Effort |
|---|---|---|---|
| PF-02 | `AppLifecycleState` manquant | `tuner_bloc.dart` | 30 min |
| PF-03 | Race `add()` après `close()` | `tuner_bloc.dart` | 5 min |
| PF-04 | `PitchResult.==` exact float | `pitch_result.dart` | 15 min |

### Backlog (optimisation)

| # | Finding | Fichier | Effort |
|---|---|---|---|
| PF-05 | Clé cache shader incomplète | `cents_bar_widget.dart` | 10 min |
| PF-06 | `Paint()` par frame (gradient) | `cents_bar_widget.dart` | 5 min |
| PF-07 | 22 trig/frame (graduations) | `tuner_needle_widget.dart` | 20 min |
| PF-08 | `late final` sémantique fragile | `tuner_needle_widget.dart` | 5 min |
| PF-09 | Deux `BlocBuilder` (60 Hz) | `tuner_screen.dart` | 10 min |

---

## Comparaison pre/post fix

| Audit | Findings bloquants | Findings sérieux | Total |
|---|---|---|---|
| AUDIT_PRE_MERGE | 1 | 3 | 10 |
| AUDIT_POST_FIX | **1** | 1 | **9** |

Les 10 findings initiaux sont résolus. La régression PF-01 est la seule
issue bloquante — conséquence d'un fix partiel sur `TunerNeedleWidget`
non reporté sur `CentsBarWidget`.

---

*harmonixTune — Audit post-fix v1.0 — Phases 1–4*
*Prochaine action : corriger PF-01 puis merger*
