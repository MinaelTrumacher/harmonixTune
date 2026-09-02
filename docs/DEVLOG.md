# harmonixTune — Journal de développement UI

> Ce document retrace **toutes les décisions** prises lors de l'implémentation des
> Phases 1 à 4, avec leur justification technique et architecturale.
> Référence : `DEV_STRATEGY.md` · `UI_DESIGN.md` · `ARCHITECTURE_FLUX.md`

---

## 1. Phase 1 — Foundation

### 1.1 `pubspec.yaml` — Choix des dépendances

**4 dépendances ajoutées :**

| Package | Version | Rôle | Pourquoi ce choix |
|---|---|---|---|
| `flutter_bloc` | `^8.1.6` | State management | Standard de l'industrie Flutter, API stable, testable |
| `equatable` | `^2.0.5` | Égalité structurelle | Évite d'implémenter `==` et `hashCode` à la main sur chaque state/event |
| `google_fonts` | `^6.2.1` | Police Inter | Téléchargement automatique, pas de fichier font à bundler manuellement |
| `gap` | `^3.0.1` | Espacement sémantique | `Gap(16)` est plus lisible que `SizedBox(height: 16)` et documente l'intention |

**`go_router` exclu volontairement** : la navigation est un `IndexedStack` fixe à 3 onglets.
go_router apporte la gestion des deep-links, des guards d'authentification, des routes
imbriquées — aucun de ces besoins n'existe en V1. Ajouter go_router ici aurait été du
sur-engineering pur.

---

### 1.2 `lib/core/constants/audio_constants.dart`

Classe abstraite `final` (non instanciable, non extensible) contenant les constantes
partagées entre les couches.

```
sampleRate        = 44100 Hz  → standard CD, compatible tous plugins Flutter audio
bufferSize        = 2048      → ~46 ms de fenêtre d'analyse (compromis latence/précision)
inTuneThresholdCents  = 2.0  → ±2 cents = "in tune" (standard accordeurs professionnels)
nearTuneThresholdCents = 5.0  → ±5 cents = zone ambre (presque juste)
minConfidence     = 0.85      → en dessous = signal trop faible, on affiche "silent"
referenceA4Hz     = 440.0     → La 440 Hz par défaut (modifiable via settings)
```

Ces seuils sont les **seuls endroits** où ces valeurs sont définies. Le BLoC et
l'Isolate (Phase 8) les liront depuis ici — jamais de magic numbers dispersés.

---

### 1.3 `lib/presentation/theme/app_colors.dart`

**Classe `abstract final`** — non instanciable, toutes les couleurs sont des constantes
statiques `const`. Pas de getter, pas de méthode : un simple dictionnaire de couleurs.

**Décisions de palette :**

- `background #0D0D14` — noir quasi-pur OLED. Sur les écrans OLED (99 % des flagship),
  les pixels noirs sont éteints → économie batterie réelle en studio ou sur scène.

- `primary #C8A84B` — or ambré, évocation directe d'une corde de guitare bronze.
  Contraste suffisant sur fond sombre sans être agressif.

- `tooLow #5B8EF0` / `tooHigh #F06050` — bleu froid pour les notes trop graves
  (évocation acoustique : grave = lourd = froid), rouge-orangé pour les notes trop
  aiguës (chaud = aigu). Cette convention est intuitive même sans lire de label.

- `inTune #4CAF50` — vert Material standard. Lisible universellement comme "correct".

**Règle d'utilisation** : seul l'indicateur d'accord (aiguille + barre de cents)
change de couleur dynamiquement. Tout le reste est statique. Raison : un changement
de couleur périphérique attire l'œil et fatigue pendant une longue session.

---

### 1.4 `lib/presentation/theme/app_text_styles.dart`

**Getters statiques** et non champs statiques. Raison : `GoogleFonts.inter()` effectue
un appel interne pour charger le style. Avec un champ `static TextStyle x = ...`,
l'initialisation a lieu au premier accès à la classe et peut être trop précoce
(avant `WidgetsFlutterBinding.ensureInitialized()`). Un getter garantit l'évaluation
paresseuse et correcte.

Police `Inter` pour les affichages texte, `RobotoMono` pour les valeurs numériques
précises (Hz, cents). Les valeurs numériques en mono évitent le saut de layout quand
les chiffres changent (chaque caractère a la même largeur).

---

### 1.5 `lib/presentation/theme/app_theme.dart`

- **`useMaterial3: true`** : nécessaire pour que `ColorScheme`, `SwitchTheme`,
  `SliderTheme` utilisent l'API moderne. Material 2 aurait des valeurs par défaut
  incompatibles avec notre thème sombre.

- **`SwitchThemeData` via `WidgetStateProperty.resolveWith`** : le switch change
  d'apparence selon son état (`selected` / non sélectionné) sans qu'on ait à créer
  un widget Switch custom. Respecte le design system sans code dupliqué.

- **Couleur overlay `0x22C8A84B`** pour le Slider : `22` en hex = 13 % d'opacité.
  Le halo du thumb est présent mais discret sur fond sombre.

- **`withValues(alpha: 0.35)`** utilisé partout à la place de `withOpacity()` —
  `withOpacity` est déprécié depuis Flutter 3.27. `withValues` opère directement
  sur le canal alpha sans perte de précision flottante.

---

### 1.6 `lib/main.dart`

```dart
WidgetsFlutterBinding.ensureInitialized();
SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
```

- `ensureInitialized()` — obligatoire avant tout appel à `SystemChrome` ou
  aux plugins natifs. Sans ça, l'appel à `setPreferredOrientations` lance une
  `FlutterError` au démarrage.

- Orientation verrouillée en portrait. Un accordeur en paysage est inutilisable
  (le cadran serait trop petit). Le verrouillage évite un comportement non testé.

---

## 2. Phase 2 — Domain

**Règle absolue de cette couche : zéro `import 'package:flutter'`.**
Le Domain doit être testable avec du pur Dart, sans moteur Flutter.
Vérifiable avec `flutter analyze` : aucune dépendance Flutter dans ces fichiers.

### 2.1 Enums

Trois enums séparés dans trois fichiers distincts :

- `TunerState` (`silent | tooLow | inTune | tooHigh`) — état calculé par l'algorithme.
  Noté `TunerState` côté Domain pour ne pas confondre avec `TunerDisplayState`
  (les sealed classes BLoC côté Présentation).

- `SweeteningStrategy` — paramètre de la `TuningConfiguration` qui détermine
  la fréquence cible calculée par le UseCase (Phase 9). Isolé ici car il est
  partagé entre le Domain et la Présentation (Settings UI).

- `InstrumentType` — détermine le nombre de cordes et les notes par défaut du
  `StringSelectorWidget`.

Un enum par fichier : convention Dart recommandée, facilite les imports sélectifs.

---

### 2.2 `PitchResult`

```dart
static const PitchResult silent = PitchResult(...)
```

La constante `silent` évite de créer un `PitchResult?` nullable partout.
Le BLoC et les widgets reçoivent toujours un `PitchResult` valide — ils n'ont
pas à gérer un `null`. Le state `TunerInitial` n'a simplement pas de pitch ;
les widgets lisent `PitchResult.silent` comme valeur par défaut.

**`copyWith` avec sentinel** : la méthode `copyWith` de `TuningConfiguration`
doit pouvoir distinguer "l'appelant a passé `null` pour `targetString`" (veut
passer en mode AUTO) de "l'appelant n'a pas mentionné `targetString`" (garder
la valeur actuelle). Dart n'a pas de paramètres optionnels distincts de `null`,
donc on utilise un objet sentinelle privé `const Object _sentinel = Object()`.

```dart
targetString: targetString == _sentinel ? this.targetString : targetString as String?
```

Sans ce pattern, `copyWith(targetString: null)` serait impossible à distinguer
de l'absence du paramètre.

---

### 2.3 `AudioRepository` (interface)

```dart
abstract interface class AudioRepository { ... }
```

`abstract interface class` est la syntaxe Dart 3 pour déclarer une interface pure :
- `abstract` → ne peut pas être instancciée directement
- `interface` → interdit l'héritage (`extends`), n'autorise que l'implémentation (`implements`)

La couche Présentation (BLoC) reçoit `AudioRepository` en injection de constructeur.
Elle ne connaît jamais `AudioRepositoryImpl` (Phase 8). Ce découplage est la
garantie que le BLoC reste testable avec un mock du repository.

---

## 3. Phase 3 — Navigation

### 3.1 `IndexedStack` vs navigation push/pop

`IndexedStack` maintient les 3 screens **en mémoire** simultanément. Le changement
d'onglet est instantané car aucun rebuild n'a lieu — seul le widget visible change.

Conséquence importante : le `TunerBloc` est créé une fois (dans `TunerScreen`) et
reste vivant tant que l'app tourne. L'accordeur continue à "écouter" même quand
l'utilisateur navigue vers l'onglet Presets. En Phase 9, on gérera ça avec
`AppLifecycleState` pour couper le micro quand l'app passe en arrière-plan,
mais l'onglet visible n'aura pas d'impact.

### 3.2 `MainShell` — `StatefulWidget`

`MainShell` est `StatefulWidget` uniquement pour stocker `_currentIndex`.
C'est le seul état local de la navigation. On aurait pu utiliser un BLoC de
navigation, mais pour 3 onglets fixes c'est du sur-engineering.

### 3.3 Stubs des screens Presets et Chords

Les stubs contiennent un texte "Phase 5" / "Phase 6" pour signaler clairement
que ces écrans sont des placeholders. Pas de `TODO` commenté dans le code —
le texte visible à l'écran est suffisant et ne pollue pas l'arbre de widgets.

---

## 4. Phase 4 — TunerScreen

C'est la phase la plus complexe. Elle réunit BLoC, CustomPainter, Ticker et
plusieurs widgets composés.

### 4.1 BLoC — Architecture des Events/States

**Events (sealed classes) :**
```
StartTuner          → démarre le mock stream (Phase 9 : stream réel)
StopTuner           → arrête le stream, émet TunerInitial
PitchReceived       → données audio (fréquence + cents), émis par le stream
ConfigChanged       → nouvelle TuningConfiguration → re-subscription
StringSelected      → sélection d'une corde (null = AUTO)
IntelliTunerToggled → active/désactive le filtre passe-bande
DebugCentsOverride  → override debug, suspend le mock
```

**States (sealed classes) :**
```
TunerInitial    → état de départ, micro inactif
TunerListening  → micro actif, contient PitchResult + TuningConfiguration + bool
```

`sealed class` (Dart 3) force le pattern matching exhaustif dans les widgets :
```dart
switch (state) {
  TunerInitial()    => ...,
  TunerListening()  => ...,
}
// Le compilateur signale si un case manque.
```

**`Equatable` sur les events/states** : les events utilisent `props` pour que BLoC
évite de retraiter deux events identiques consécutifs. Pour les states, `Equatable`
permet à `BlocBuilder` de ne rebuilder que si l'état a réellement changé.

---

### 4.2 BLoC — Mock Stream

```dart
Stream<_MockSample>.periodic(
  const Duration(milliseconds: 16), // ~60 Hz
  (_) { final cents = sin(_mockTick++ * 0.04) * 35.0; ... }
)
```

**Pourquoi 16 ms ?** C'est la fréquence cible d'un pipeline audio à 60 fps.
En Phase 9, le stream réel émettra à la même fréquence (buffer de 2048 samples
à 44100 Hz ≈ 46 ms, mais le plugin peut bufferer plus finement).

**Pourquoi sinusoïdal ?** Le sinus oscille naturellement entre -35 et +35 cents,
traversant les zones `tooLow`, `inTune` et `tooHigh` de façon visible. C'est
le meilleur test visuel pour l'animation de l'aiguille.

**`_MockSample` (classe privée)** : le stream interne émet des `_MockSample` et
non des `PitchResult` directement. Raison : le BLoC convertit les données brutes
en entité Domain dans `_pitchFromCents()`. Ce découplage mimique exactement ce
que fera l'Isolate en Phase 8 — qui enverra des données brutes (Hz, cents) et
non des `PitchResult` construits.

**Pattern de re-subscription :**
```dart
Future<void> _subscribe() async {
  await _subscription?.cancel(); // annule l'ancien flux AVANT d'en ouvrir un
  _subscription = null;
  _subscription = _mockStream().listen(...);
}
```

**Pourquoi `restartable()` sur `ConfigChanged` et pas un verrou manuel ?**

Le transformer par défaut de flutter_bloc est `sequential()` : les events sont mis en
file et traités un par un. La race condition classique (deux `_subscribe()` en
parallèle) n'existe donc **pas** dans l'implémentation actuelle — le second
`ConfigChanged` ne sera dépilé qu'après que le premier handler soit entièrement
terminé, `await` inclus.

Malgré cela, `restartable()` est utilisé sur `ConfigChanged` pour deux raisons :

1. **Intention explicite** : `restartable()` dit "si une nouvelle config arrive,
   la précédente est obsolète, abandonne-la". Sans ça, cette intention est cachée
   dans le pattern `cancel → null → listen`, invisible à la lecture.

2. **Protection contre les refactorisations futures** : si un autre transformer
   (`concurrent()`, `droppable()`) est un jour ajouté sur un handler voisin, ou si
   `_subscribe()` est appelé depuis plusieurs events en concurrence, `restartable()`
   garantit la robustesse sans modification supplémentaire.

```dart
// Dans le constructeur du BLoC :
on<ConfigChanged>(_onConfigChanged, transformer: restartable());
// → le handler précédent est annulé dès qu'un nouveau ConfigChanged arrive,
//   sans attendre que l'await _subscription?.cancel() se termine.
```

**`DebugCentsOverride`** : suspend le mock (`cancel()`) et émet un `TunerListening`
avec la valeur fixée par le slider. Le mock reprend quand `StartTuner` est reçu
(déclenché par `onChangeEnd` du Slider). Ce mécanisme permet de tester tous les
états visuels sans signal audio.

---

### 4.3 `TunerNeedleWidget` — La décision la plus critique

#### Pourquoi pas `AnimationController` ?

Le stream audio arrive toutes les ~16 ms. Si on lance une animation de durée fixe
(ex. 120 ms) à chaque nouvelle valeur reçue, l'`AnimationController` est
interrompu et redémarré ~7 fois avant d'avoir fini sa courbe. Résultat :
bégaiement visible, saturation CPU, comportement imprévisible.

#### Solution : Lerp continu piloté par un `Ticker`

```dart
_ticker = createTicker((_) {
  final next = _displayAngle + _alpha * (_targetAngle - _displayAngle);
  if ((next - _displayAngle).abs() > 0.0001) {
    setState(() => _displayAngle = next);
  }
})..start();
```

Le `Ticker` est appelé à **chaque vsync** (60 ou 120 Hz selon l'écran).
À chaque appel, il interpole `_displayAngle` de 25 % vers `_targetAngle`.
`_targetAngle` est mis à jour par le `BlocListener` (hors vsync, à la fréquence audio).

**Choix d'`alpha = 0.25` :**
| Alpha | Comportement |
|---|---|
| 0.10 | Très lissé, retard ~200 ms ressenti — comme du coton |
| 0.25 | Réactif, suit les variations sans tremblement sur notes instables ✓ |
| 0.50 | Quasi-instantané, tremble sur les harmoniques parasites |
| 1.00 | Pas de lissage — équivalent à AnimationController durée 0 |

#### Géométrie du cadran (`_NeedlePainter`)

**Centre** = `Offset(size.width / 2, size.height)` — coin bas-centre du widget.
L'aiguille se projette vers le haut depuis ce point.

**Arc de fond** : `drawArc(rect, π, π)` = startAngle π (ouest), sweepAngle π.
Dans le canvas Flutter (axe y vers le bas) : depuis l'ouest, un sweep positif
va vers le nord (haut écran) puis vers l'est. C'est le demi-cercle supérieur. ✓

**Formule de l'angle de l'aiguille :**
```
drawingAngle = 3π/2 + displayAngle
```
- `displayAngle = 0`    → `3π/2` → `sin = -1` → pointe vers le haut ✓
- `displayAngle = -π/2` → `π`    → `cos = -1` → pointe vers la gauche ✓
- `displayAngle = +π/2` → `2π`   → `cos = +1` → pointe vers la droite ✓

**Pourquoi ce signe fonctionne-t-il ?**
Dans le canvas Flutter, l'axe Y pointe vers le bas et les angles croissants tournent
dans le **sens horaire** (Est → Sud → Ouest → Nord). En partant de `3π/2` (Nord) :

- Un `displayAngle` **positif** (note trop aiguë) tourne dans le sens horaire
  depuis le Nord → vers l'Est (droite de l'écran). ✓
- Un `displayAngle` **négatif** (note trop grave) tourne dans le sens anti-horaire
  depuis le Nord → vers l'Ouest (gauche de l'écran). ✓

Cette convention **s'aligne naturellement** avec la définition de `displayAngle` :
```dart
_targetAngle = (centsDeviation / 50.0) * (pi / 2);
// cents positif (trop aigu) → angle positif → horaire depuis le haut → droite ✓
// cents négatif (trop grave) → angle négatif → anti-horaire depuis le haut → gauche ✓
```
Sans l'inversion de l'axe Y du canvas Flutter, il faudrait inverser le signe.

**Zone "In Tune"** : arc vert centré sur `3π/2` (haut), demi-angle `= (2/50) × (π/2)`.
L'arc est dessiné **avant** l'aiguille pour être visuellement en dessous d'elle.

**`RepaintBoundary`** : isole le `CustomPaint` de l'arbre parent. Quand le `Ticker`
appelle `setState`, seul le sous-arbre du widget est rebuilté. Les autres widgets
de la `TunerScreen` (NoteDisplay, StringSelector…) ne sont pas touchés.

**`shouldRepaint`** : retourne `true` seulement si `displayAngle`, `needleColor`
ou `tunerState` ont changé. Évite les repaints inutiles si le Ticker tourne mais
que l'aiguille a convergé (écart < 0.0001).

---

### 4.4 `CentsBarWidget` — Ticker indépendant

**Un `Ticker` par widget**, pas un `Ticker` partagé avec le `TunerNeedleWidget`.

Raison : si un Ticker parent pilotait les deux, la valeur interpolée devrait
descendre dans l'arbre via `setState` ou `ValueNotifier`. Cela invaliderait
les `RepaintBoundary` intermédiaires à chaque frame, annulant leur bénéfice.
Chaque widget isole son propre cycle de repaint.

**Gradient de la barre** (`LinearGradient`) : bleu → gris → rouge.
Le gradient est statique (il ne change pas en fonction de la position de la bille).
Seule la bille se déplace. Cela évite de recalculer le shader à chaque frame.

**Halo autour de la bille** (cercle semi-transparent) : donne de la profondeur
sans alourdir le rendu. L'opacité est `0.18` — juste visible sur fond sombre.

---

### 4.5 `NoteDisplayWidget`

`BlocBuilder` simple, pas de `Ticker`. Le texte de la note change rarement
(seulement quand l'utilisateur s'approche d'une autre note). Il n'a pas
besoin d'animation lerp — le changement brutal de "E4" à "F4" est attendu
et sémantiquement correct (on a changé de note cible).

La valeur Hz est affichée avec `mono` (RobotoMono) : les chiffres ne causent
pas de micro-saut de layout quand ils changent (caractères à largeur fixe).

---

### 4.6 `StringSelectorWidget`

- **`AnimatedOpacity`** (200 ms) : quand le mode AUTO est activé, tous les boutons
  passent à `opacity = 0.4` progressivement — pas un toggle brutal.

- **`AnimatedContainer`** (150 ms) : la bordure du bouton sélectionné passe de
  `AppColors.divider` à `AppColors.primary` avec une transition fluide.

- **Tap pour désélectionner** : si le bouton déjà sélectionné est retappé,
  on envoie `StringSelected(null)` → mode AUTO. Pattern toggle naturel.

- En mode AUTO (`selected == null`) : `onTap = null` sur le `GestureDetector`.
  Flutter désactive le feedback tactile automatiquement.

---

### 4.7 `IntelliTunerToggle`

Utilise le `Switch` du thème (configuré dans `AppTheme` via `SwitchThemeData`).
Pas de widget Switch custom — le thème fait le travail.

Un `Tooltip` avec le texte d'explication est ajouté sur l'ensemble du Row.
L'utilisateur long-presse pour voir l'explication — comportement standard Material.

---

### 4.8 `TunerScreen` — Composition et `BlocProvider`

```dart
return BlocProvider(
  create: (_) => TunerBloc()..add(const StartTuner()),
  child: const _TunerView(),
);
```

Le `BlocProvider` est dans `TunerScreen` (pas dans `MainShell`).
Raison : le `TunerBloc` est scoped à l'écran Tuner. Si on le mettait dans
`MainShell`, il serait disponible dans les écrans Presets et Chords, ce qui
n'a aucun sens et polluerait le context.

`..add(const StartTuner())` : cascade Dart. Le BLoC est créé ET le stream
est démarré dans la même expression. L'UI ne reste jamais dans `TunerInitial`
plus de quelques millisecondes.

**`Spacer()`** entre le sélecteur de cordes et le debug slider : pousse le
slider de debug en bas d'écran, hors de la zone de lecture principale.
Le debug reste visible mais ne perturbe pas le layout de production.

---

### 4.9 `AppHeader` (shared)

Widget réutilisable placé dans `presentation/shared/`. Il sera utilisé par
`TunerScreen` (Phase 4), `PresetsScreen` (Phase 5) et `ChordsScreen` (Phase 6).

Le titre reçoit la couleur `AppColors.primary` (ambre doré) pour être distinctif
sans être un `AppBar` standard (qui consommerait 56 dp de hauteur supplémentaire).

---

## 5. Décisions transversales

### 5.1 `withValues(alpha: x)` partout

`withOpacity()` est déprécié depuis Flutter 3.27 et signale un warning IDE.
`withValues(alpha: x)` opère directement sur le canal alpha du `Color` sans
conversion intermédiaire en `double` 32 bits. Tous les fichiers utilisent
`withValues`.

### 5.2 Aucun magic number dans les widgets

Les seuils (`inTuneThresholdCents`, etc.) viennent de `AudioConstants`.
Les couleurs viennent de `AppColors`. Les styles viennent de `AppTextStyles`.
Aucun literal `Color(0xFF...)` ou `fontSize: 14` dans un widget.

### 5.3 `abstract final class` pour les classes utilitaires

`AppColors`, `AppTextStyles`, `AppTheme`, `AudioConstants` sont tous
`abstract final` :
- `abstract` → ne peuvent pas être instanciées avec `new`
- `final` → ne peuvent pas être étendues

C'est l'équivalent Dart d'une "utility class" en Java/Kotlin. Pas de constructeur
privé nécessaire — le compilateur l'interdit nativement.

### 5.4 Test smoke corrigé

Le test de départ `widget_test.dart` référençait `MyApp` (la classe par défaut
de Flutter). Après nettoyage de `main.dart`, le test a été mis à jour pour
pointer sur `HarmonixTuneApp` et vérifier que l'app démarre sans crash.

`flutter analyze` retourne **`No issues found!`** sur la totalité du projet.

---

## 6. Ce qui n'a PAS été fait (volontairement)

| Élément | Raison de l'absence |
|---|---|
| `go_router` | 3 onglets fixes, zéro deep-link — sur-engineering |
| `PresetsBloc` / `ChordsBloc` | Phase 5 et 6, pas encore démarrées |
| `AudioRepository` impl | Phase 8 — micro pas encore branché |
| Strategy Pattern (YIN) | Phase 7 — après la validation de l'UI |
| `flutter_lints` corrections | Le linter est à `^6.0.0`, aucun warning produit |
| Animations "In Tune" one-shot | Prévu mais reporté après validation visuelle |
| `SettingsSheet` | Phase 6 (ChordsScreen) |

---

## 7. Résultat final

```
28 fichiers créés
 0 erreurs flutter analyze
 0 warnings de dépréciations
 4 dépendances installées
```

L'app est lancable avec `flutter run`.
L'aiguille anime de -35 à +35 cents (sinusoïdal).
Le slider de debug (kDebugMode) permet de forcer n'importe quelle valeur de -50 à +50 cents.
Les états visuels (bleu / ambre / vert / rouge) sont tous fonctionnels.

---

*harmonixTune — DEVLOG v1.0 — Phases 1 à 4 complétées*
