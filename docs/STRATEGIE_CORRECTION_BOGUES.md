# harmonixTune — Stratégie de correction des bogues

**Statut :** Implémenté — BUG-01/02/03 codés et testés (`flutter analyze` +
`flutter test` : 226 tests, 0 échec). Recette manuelle sur device réel
(NAV-02, LIFE-01/02/03, PERM-02→05, ITN-01/02/03) restant à rejouer avant
clôture définitive, cf. `CAHIER_DE_RECETTES.md`.
**Référence :** `PLAN_CORRECTION_BOGUES.md` (constat + cause racine + pistes),
`CAHIER_DE_RECETTES.md` (scénarios à rejouer), `EXIGENCES_SECURITE.md` (§1 —
coupure micro).

> Ce document tranche les pistes laissées ouvertes dans
> `PLAN_CORRECTION_BOGUES.md`, décrit le correctif concret par bug (fichiers,
> code cible, cas limites) et fixe l'ordre d'exécution. Les sections "Tests"
> de chaque bug indiquent, en plus du plan d'origine, les écarts constatés
> lors de l'implémentation.

---

## 1. Ordre de traitement retenu

| Ordre | Bug | Raison |
|---|---|---|
| 1 | **BUG-02** (reprise après pause) | Bloquant release explicite, cause 4 des 6 anomalies KO. Touche `TunerBloc.didChangeAppLifecycleState` — base commune avec BUG-03. |
| 2 | **BUG-03** (micro actif hors onglet) | Même zone de code (cycle de vie de l'écoute), et prérequis pour que **PERM-05 soit rejoué pour la bonne raison** (note du plan : le succès actuel de PERM-05 est probablement un artefact du redémarrage process Android, pas une reprise gérée par le code — traiter BUG-02 et BUG-03 avant de revalider PERM-05). Impacte aussi `EXIGENCES_SECURITE.md §1` (coupure micro hors premier plan applicatif). |
| 3 | **BUG-01** (Intelli-Tuner auto) | Indépendant des deux premiers (isolate + BLoC, pas de cycle de vie). Peut être traité en parallèle si besoin, mais placé en dernier car moins bloquant ("à confirmer" dans le plan) et parce que sa correction interagit avec le comportement du filtre IIR qu'il vaut mieux valider sur une base stable (écoute qui démarre/s'arrête correctement).

Les trois correctifs touchent des mécanismes distincts (cycle de vie app,
visibilité d'onglet, filtrage de confiance) : aucune dépendance de code
stricte ne les lie, mais 1→2→3 minimise le risque de devoir retester à
plusieurs reprises les mêmes scénarios de recette.

---

## 2. BUG-02 — L'écoute ne reprend jamais après un retour au premier plan

### Décision

Piste retenue du plan : remplacer le test sur `this.state` (déjà écrasé par
`TunerInitial` au moment du `resumed`) par un flag mémorisé **avant**
l'émission de `TunerInitial`.

### Correctif ciblé — `tuner_bloc.dart`

```dart
bool _wasListeningBeforePause = false;

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _wasListeningBeforePause = this.state is TunerListening;
    if (!isClosed) add(const StopTuner());
  } else if (state == AppLifecycleState.resumed && _wasListeningBeforePause) {
    _wasListeningBeforePause = false;
    if (!isClosed) add(const StartTuner());
  }
}
```

Point clé : le flag est capturé **avant** `add(StopTuner())`, donc avant que
`_onStop` n'émette `TunerInitial`. Il est consommé (remis à `false`) dès la
reprise, qu'elle réussisse ou non — pas de double déclenchement possible.

`AppLifecycleState` a aussi les valeurs `inactive`/`hidden` (notification
pull-down iOS, split-screen Android) — le code ne réagit qu'explicitement à
`paused`/`resumed`, donc aucun `StartTuner`/`StopTuner` intempestif sur ces
transitions intermédiaires. Pas un correctif à faire, mais un point à
vérifier en recette exploratoire iOS si la cible inclut iOS (le passage par
`inactive` avant `paused` y est systématique).

### Idempotence StartTuner / StopTuner (prérequis avant BUG-03)

`Bloc.on<E>` ne sérialise les événements **qu'au sein d'un même type**
(`asyncExpand` sur le sous-flux filtré de ce type). `StartTuner` et
`StopTuner` étant deux types distincts, sans transformer explicite ils
peuvent s'exécuter **en parallèle**. Or `_subscribeToRepo()` a un point
`await` (`await _subscription?.cancel()`) avant d'écraser `_subscription` —
un enchaînement rapide `StartTuner → StopTuner → StartTuner` (typiquement un
changement d'onglet A→B→A en moins d'une frame, cf. BUG-03 §3) peut donc
laisser deux souscriptions actives : `AudioRepositoryImpl._start()` réassigne
`_isolate`/`_workerPort`/`_micSubscription`/`_controller` sans jamais fermer
l'instance précédente si un second appel écrase les champs avant que le
premier n'ait fini d'écrire les siens. Résultat concret : un isolate + une
capture micro orphelins, actifs en arrière-plan indéfiniment — soit
exactement le manquement que BUG-03 doit corriger, réintroduit par un autre
chemin.

Correctif : sérialiser `_onStart`/`_onStop` entre eux via une file d'attente
partagée, indépendamment du type d'événement :

```dart
// Chaque appel rallonge la chaîne d'un maillon ; le maillon précédent est
// éligible au GC dès qu'il complète (`.then` ne retient que son
// prédécesseur immédiat) — pas d'accumulation mémoire tant que Start/Stop
// restent des événements pilotés par l'utilisateur/le lifecycle (pas un
// flux haute fréquence).
Future<void> _lifecycleLock = Future.value();

Future<void> _guarded(Future<void> Function() action) {
  // `isClosed` revérifié juste avant d'exécuter l'action : une action mise
  // en file peut se retrouver à s'exécuter après `close()` (ex. changement
  // d'onglet suivi immédiatement d'une navigation qui détruit le widget,
  // cf. §3 "angle mort dispose()") — sans ce guard, _subscribeToRepo()
  // relancerait une souscription micro sur un bloc déjà fermé.
  final result = _lifecycleLock.then((_) => isClosed ? null : action());
  _lifecycleLock = result.catchError((_) {});
  return result;
}

Future<void> _onStart(StartTuner _, Emitter<TunerDisplayState> emit) =>
    _guarded(_subscribeToRepo);

Future<void> _onStop(StopTuner _, Emitter<TunerDisplayState> emit) =>
    _guarded(() async {
      await _subscription?.cancel();
      _subscription = null;
      await _audioRepository.stop();
      if (!isClosed) emit(const TunerInitial());
    });
```

Ce correctif est un prérequis de BUG-02 (pas seulement de BUG-03) : c'est
`didChangeAppLifecycleState` qui déclenche déjà `StartTuner`/`StopTuner` de
façon rapprochée (ex. `paused` suivi de près d'un `resumed` sur un
double-tap accidentel du bouton Home). À traiter dans la même PR que le flag
`_wasListeningBeforePause`.

### Cas limites vérifiés

- **Arrêt manuel puis mise en arrière-plan** : `this.state` est déjà
  `TunerInitial` au moment du `paused` → flag `false` → pas de redémarrage
  intempestif au retour. Comportement voulu (respecte l'action explicite de
  l'utilisateur).
- **Permission révoquée pendant la pause (PERM-02/03/04)** : au retour,
  `StartTuner` relance `_subscribeToRepo()` → `RecordMicrophoneDataSource`
  détecte l'absence de permission → `AudioPermissionException` →
  `PermissionDenied` → `TunerPermissionDeniedState`. La chaîne cassée
  aujourd'hui (jamais atteinte car `_subscribeToRepo()` jamais rappelée) est
  donc réparée comme effet de bord direct de ce correctif — confirme
  l'analyse du plan ("un seul correctif devrait résoudre 4 des 6 anomalies").
- **Slider debug (`DebugCentsOverride`) puis mise en pause** : l'état est
  `TunerListening` (valeur figée) au moment du `paused` → flag `true` → au
  retour, `StartTuner` relance la vraie souscription micro. Comportement
  acceptable (le mode debug n'est pas destiné à survivre à un cycle de vie).

### Tests

- Test `bloc_test` sur `TunerBloc` : simuler `didChangeAppLifecycleState`
  directement (méthode publique héritée de `WidgetsBindingObserver`, pas
  besoin de monter un widget) pour les 3 séquences ci-dessus.
- Test dédié à la file d'attente : déclencher `StartTuner` puis
  immédiatement `StopTuner` puis `StartTuner` sans attendre entre les
  `add()` → vérifier avec `verifyInOrder([...])` (mocktail) la **séquence**
  exacte `streamPitch` → `stop` → `streamPitch`, pas seulement le nombre
  d'appels. Un test par compteurs (`verify(...).called(n)`) ne détecterait
  pas un réordonnancement/chevauchement des appels — c'est justement la
  race condition qu'on corrige, donc le test doit pouvoir la faire échouer
  si le guard `isClosed`/la file `_guarded` est retiré par erreur.
- Recette à rejouer : **LIFE-01, LIFE-02, LIFE-03, PERM-02, PERM-03, PERM-04**,
  puis **PERM-05** en confirmant qu'il passe désormais par le chemin de code
  (et pas par un redémarrage process fortuit — cf. mise en garde du plan).

---

## 3. BUG-03 — Le micro continue d'écouter en dehors de l'onglet Tuner

### Décision

Ne pas ajouter de nouvelle dépendance (`visibility_detector` n'est pas dans
`pubspec.yaml`, et le besoin ne le justifie pas ici) : l'index courant est
déjà connu de `MainShell`, il suffit de le faire descendre jusqu'à
`TunerScreen`. On tranche donc explicitement la question ouverte du plan en
faveur de **l'écoute coupée hors de l'onglet Tuner** (et non "comportement
voulu" à documenter) : c'est cohérent avec `EXIGENCES_SECURITE.md §1`, qui
liste déjà ce comportement comme non conforme à l'exigence "couper le micro
dès que l'app n'est plus au premier plan [ou onglet actif]".

### Correctif ciblé

**`main_shell.dart`** — transmettre l'état actif à l'écran Tuner :

```dart
final screens = [
  TunerScreen(isActive: _currentIndex == 0),
  PresetsScreen(repository: widget.tuningProfileRepository),
  const ChordsScreen(),
];
```

**`tuner_screen.dart`** — `TunerScreen` passe de `StatelessWidget` à
`StatefulWidget` pour piloter le cycle de vie du `TunerBloc` indépendamment
des rebuilds (le `BlocProvider(create: ...)` actuel ne convient plus car on
doit réagir à un changement de `widget.isActive` sans recréer le bloc).

Point ajouté suite à revue : la construction actuelle
(`TunerBloc(AudioRepositoryImpl(RecordMicrophoneDataSource()))`) est en dur
dans `tuner_screen.dart` — aucun seam d'injection n'existe aujourd'hui pour
`TunerScreen` (contrairement à `TunerBloc` lui-même, déjà testé en isolation
via `TunerBloc(mockRepo)` dans `tuner_bloc_test.dart`). Le test widget prévu
plus bas (vérifier `Start`/`Stop` sur changement d'onglet) ne peut pas
instancier de vrai microphone en environnement de test : `TunerScreen` doit
donc accepter une factory optionnelle, sur le même principe d'injection par
constructeur déjà utilisé pour `TunerBloc` (pas de framework DI à
introduire) :

```dart
class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key, this.isActive = true, TunerBloc Function()? blocBuilder})
      : _blocBuilder = blocBuilder;

  final bool isActive;
  final TunerBloc Function()? _blocBuilder;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  late final TunerBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = (widget._blocBuilder ??
        () => TunerBloc(AudioRepositoryImpl(RecordMicrophoneDataSource())))();
    if (widget.isActive) _bloc.add(const StartTuner());
  }

  @override
  void didUpdateWidget(covariant TunerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _bloc.add(widget.isActive ? const StartTuner() : const StopTuner());
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: _bloc, child: const _TunerView());
  }
}
```

Le reste de `_TunerView`/`_TunerContent`/`_PermissionDeniedView` est inchangé
(ils consomment le bloc via `context.read`/`BlocBuilder`, indifférents à la
façon dont il a été fourni).

`dispose()` (ligne `_bloc.close()`) peut s'exécuter alors qu'une action est
encore en file dans `_guarded` (ex. changement d'onglet suivi immédiatement
d'une navigation qui démonte `TunerScreen`) : c'est couvert par le guard
`isClosed` ajouté dans `_guarded` (§2), pas par un correctif séparé ici.

### Interaction avec BUG-02 (vérifiée)

- Backgrounding pendant que l'onglet Tuner est actif et en écoute → BUG-02
  gère l'arrêt/reprise comme décrit en §2, sans interférence.
- Backgrounding pendant que l'onglet Tuner est **inactif** (déjà stoppé par
  ce correctif) → `didChangeAppLifecycleState` capture `_wasListeningBeforePause
  = false` (l'état est déjà `TunerInitial`) → pas de redémarrage au retour
  tant que l'utilisateur reste sur un autre onglet. Comportement correct.
- Enchaînement rapide de changements d'onglet (`StartTuner`/`StopTuner`
  rapprochés émis par `didUpdateWidget`, ex. A→B→A en moins d'une frame) :
  couvert par la file d'attente `_guarded` introduite en §2 — sans elle, ce
  scénario pourrait faire fuiter un isolate/une capture micro orpheline
  (cf. §2 "Idempotence StartTuner / StopTuner"), donc ce correctif dépend
  strictement de celui de BUG-02 et ne doit pas être mergé seul.

### Tests

**Implémenté** (`tuner_screen_test.dart`) — écart au plan initial, documenté
ici : la version d'origine envisageait un unique test avec `TunerBloc(mockRepo)`
réel et `verifyInOrder` sur les appels au repo à travers 3 `pumpWidget`
successifs. En pratique, `flutter_test` tourne dans une zone `FakeAsync` où
les micro-tâches issues du pipeline d'événements d'un vrai `Bloc` (par
défaut *concurrent*, cf. `bloc` v8.1.4) ne se relancent pas de façon fiable
au travers de plusieurs `pumpWidget()` rapprochés sans transformer dédié
côté test — au-delà du premier cycle Start, les appels `stop()`/`streamPitch()`
suivants n'étaient pas garantis d'avoir été traités au moment du `verify`.
Plutôt que de complexifier le test avec un pompage manuel du scheduler (fragile,
couplé aux détails d'implémentation de `bloc`), le test a été scindé en deux
groupes, chacun visant une seule responsabilité :
- **Montage initial** (`TunerBloc(mockRepo)` réel, un seul `pumpWidget`) :
  vérifie que `isActive` détermine bien l'appel (ou non) à `streamPitch()`
  au premier rendu.
- **Transitions `isActive`** (`MockTunerBloc` — même pattern que
  `intelli_tuner_toggle_test.dart`) : vérifie directement que
  `didUpdateWidget` appelle `bloc.add(StartTuner()/StopTuner())` dans le bon
  ordre (`verifyInOrder`), sans dépendre du traitement interne de ces
  événements par `TunerBloc` — déjà couvert de façon déterministe par le test
  `bloc_test` "sérialise StartTuner/StopTuner rapprochés" du §2.

Séparément, le rendu complet de `TunerScreen` (thème `GoogleFonts` réel,
pas de `Scaffold` autour de `_TunerContent`) dépasse la taille de surface de
test par défaut (800×600) → overflow de layout sans rapport avec BUG-03.
Chaque test agrandit la surface (`tester.binding.setSurfaceSize`) et
consomme l'exception de rendu via `tester.takeException()` pour ne pas la
laisser faire échouer le test.
- Recette à rejouer : **NAV-02**, puis re-vérifier absence de régression sur
  **LIFE-01/02/03** et **PERM-02→05** (traité en même zone de code que
  BUG-02).
- `EXIGENCES_SECURITE.md §1` mis à jour (🔴 → ✅) en reflétant le correctif
  code + tests automatisés ; la recette manuelle NAV-02 sur device réel reste
  à rejouer avant clôture définitive du point.

---

## 4. BUG-01 — L'Intelli-Tuner ne s'active jamais automatiquement

### Décision

Option A du plan retenue : **arrêter de filtrer en silence dans l'isolate
quand une corde cible est sélectionnée**, et laisser le filtrage de confiance
au seul niveau où il a un sens fonctionnel distinct :
- **Mode AUTO** (`config.targetString == null`) : on ne veut pas afficher de
  note peu fiable → le filtre dans l'isolate reste pertinent ici.
- **Mode MANUEL** (`config.targetString != null`) : une confiance faible est
  justement le signal qui doit déclencher l'auto-activation du filtre IIR
  (scénario A2/ITN-01) → le résultat doit remonter au BLoC quel que soit son
  niveau de confiance.

Option B (déplacer l'auto-activation dans l'isolate) est écartée : elle
mélangerait une décision d'état applicatif (activer l'Intelli-Tuner) avec la
couche DSP pure, et compliquerait les tests unitaires du `TunerBloc` (il
faudrait alors tester ce comportement via les messages d'isolate plutôt que
directement sur le bloc).

### Correctif ciblé — `audio_isolate_worker.dart:108-111`

```dart
final detected = detector.detect(samples);
if (detected == null) return;
final belowConfidence = detected.confidence < AudioConstants.minConfidence;
if (belowConfidence && config.targetString == null) {
  // Mode AUTO : une détection peu fiable ne doit pas s'afficher.
  return;
}
```

`tuner_bloc.dart:77-82` (`_onPitchReceived`) n'a **pas besoin d'être modifié**
sur le plan logique : la condition `result.confidence < AudioConstants.minConfidence`
devient enfin atteignable une fois que l'isolate transmet les résultats à
faible confiance en mode manuel.

### Cas limite à trancher (décision à prendre avec le porteur de projet)

Le plan signale un risque : activer le filtre IIR sur un **échantillon
isolé** à faible confiance plutôt que sur une tendance, avec un risque UX
concret sur un accordeur (flicker on/off perceptible à l'oreille). Point
révisé suite à revue : plutôt que de différer systématiquement ce risque à
un futur bug, le coût d'un garde-fou est faible à ajouter maintenant (un
compteur `int` local au bloc) contre le coût d'un aller-retour recette
complet si le comportement s'avère trop nerveux en pratique. Deux options,
à trancher avant l'implémentation de BUG-01 — pas de valeur par défaut
imposée ici :

- **Option 1 (minimale, conforme strictement à la recette actuelle)** :
  activer dès la première détection sous le seuil, comme décrit ci-dessus.
  Rien à ajouter, comportement du scénario A2 tel quel.
- **Option 2 (garde-fou low-cost)** : exiger N détections consécutives sous
  le seuil avant d'activer (`_lowConfidenceStreak`, remis à 0 dès qu'une
  détection repasse au-dessus du seuil) :
  ```dart
  int _lowConfidenceStreak = 0;
  // dans _onPitchReceived, avant la condition d'auto-activation :
  if (result.confidence < AudioConstants.minConfidence) {
    _lowConfidenceStreak++;
  } else {
    _lowConfidenceStreak = 0;
  }
  // condition d'activation : ... && _lowConfidenceStreak >= 3 && ...
  ```
  Nécessite de fixer une valeur de N (arbitraire sans mesure terrain) et
  d'ajouter le scénario "activation retardée de N détections" au cahier de
  recettes ITN-01.

Recommandation : partir sur l'Option 1 pour rester strictement dans le
périmètre du cahier de recettes actuel, mais valider le flicker en recette
exploratoire **avant** de considérer BUG-01 clos — si le flicker est
audible, basculer sur l'Option 2 dans la foulée plutôt que d'ouvrir un
nouveau ticket.

### Impact sur ITN-03 (désélection de corde)

Aucun impact : `_onStringSelected` remet déjà `_intelliTunerEnabled = false`
et `intelliTunerActive: false` sur `clearTargetString`, indépendamment de ce
correctif.

### Tests

**Implémenté** — écart au plan initial : fabriquer un signal PCM réel
produisant une confiance YIN non-null mais `< 0.85` s'est avéré très
instable en calibration (comportement "falaise" du détecteur : quasi aucune
valeur de confiance intermédiaire entre ~0.90 et `null`, que ce soit avec du
bruit blanc ou avec le transitoire du filtre IIR en mode Intelli-Tuner —
buffer 1 retourne directement `null`, pas une confiance basse). Un test
d'intégration isolate basé sur un tel signal aurait donc été fragile/non
reproductible. La logique de seuil a été extraite dans une fonction pure
`shouldForwardPitch(confidence, config)`, top-level et annotée
`@visibleForTesting` (package `meta`, ajouté en dépendance directe dans
`pubspec.yaml` — utilisé jusque-là uniquement en transitif), testée
directement avec des valeurs de confiance synthétiques dans
`audio_isolate_worker_test.dart`. Les tests d'intégration isolate déjà
existants dans ce fichier (détection réelle A4/E2/etc.) servent de
non-régression complémentaire.

- Test `bloc_test` sur `TunerBloc._onPitchReceived` : déjà présent avant ce
  chantier (`tuner_bloc_test.dart`, groupe `PitchReceived`) et passait déjà
  — logique, puisque ce test exerce le BLoC directement sans passer par
  l'isolate, donc sans jamais toucher au bug (qui vivait uniquement côté
  isolate). Aucune modification nécessaire ici.
- Recette à rejouer : **ITN-01, ITN-02, ITN-03**.

---

## 5. Stratégie de tests globale

| Niveau | Outil | Portée |
|---|---|---|
| Unitaire BLoC | `bloc_test` (déjà en dépendance) | `_wasListeningBeforePause` + file `_guarded` (§2), auto-activation Intelli-Tuner (§4) |
| Unitaire DSP | `test` pur Dart | Seuil de confiance conditionnel par mode (§4) |
| Widget | `flutter_test` | Changement d'onglet → Start/Stop via `blocBuilder` injecté (§3) |
| Recette manuelle | `CAHIER_DE_RECETTES.md` | Rejouer LIFE-01/02/03, PERM-02→05, NAV-02, ITN-01/02/03 dans cet ordre après chaque correctif (voir §1) |

Aucun de ces trois correctifs ne touche au stockage Hive, à la télémétrie ni
au build/signature — pas d'impact sur les autres sections de
`EXIGENCES_SECURITE.md`.

---

## 6. Ordre d'exécution recommandé

```
Étape 1 — BUG-02 (tuner_bloc.dart)
  → _wasListeningBeforePause
  → File d'attente _guarded (StartTuner/StopTuner) — prérequis de BUG-03
  → Tests bloc_test (lifecycle + enchaînement rapide Start/Stop)
  → Rejouer LIFE-01/02/03, PERM-02/03/04, puis PERM-05

Étape 2 — BUG-03 (main_shell.dart, tuner_screen.dart)
  → TunerScreen en StatefulWidget + isActive + blocBuilder injectable
  → Test widget changement d'onglet (rapide inclus)
  → Rejouer NAV-02 + non-régression LIFE/PERM
  → Mettre à jour EXIGENCES_SECURITE.md §1 (🔴 → ✅)

Étape 3 — BUG-01 (audio_isolate_worker.dart)
  → Trancher Option 1 vs Option 2 (§4) avant codage
  → Filtrage de confiance conditionnel au mode
  → Tests worker + bloc_test
  → Rejouer ITN-01/02/03, valider absence de flicker
```

Étape 2 dépend strictement de la file `_guarded` livrée en étape 1 (cf. §3
"Interaction avec BUG-02") — ne pas merger BUG-03 sans elle. Étape 3 reste
indépendante des deux premières.

---

*harmonixTune — STRATEGIE_CORRECTION_BOGUES v2.0 (implémenté)*
