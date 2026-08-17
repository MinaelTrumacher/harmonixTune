# harmonixTune — Architecture & Flux de Données

> **Périmètre de ce document** : Flux de données audio de bout en bout, contrats entre couches,
> et mécanique de rendu UI temps réel, **à jour par rapport au code réel** (module Tuner).
> Complémentaire de `UI_DESIGN.md`, `DOC_REALISATION.md` et `STRATEGIE_CORRECTION_BOGUES.md`
> (qui détaille les correctifs de cycle de vie repris en §4 ici).

---

## 1. Vue d'ensemble des couches (Clean Architecture)

```
┌─────────────────────────────────────────────────────────┐
│  PRESENTATION                                           │
│  TunerScreen · TunerBloc · Ticker · CustomPainter      │
├─────────────────────────────────────────────────────────┤
│  DOMAIN                                                 │
│  PitchResult · TuningConfiguration                      │
├─────────────────────────────────────────────────────────┤
│  DATA                                                   │
│  AudioRepositoryImpl · RecordMicrophoneDataSource       │
│  Isolate Audio (audioIsolateEntryPoint)                 │
└─────────────────────────────────────────────────────────┘
```

**Règle stricte** : une couche ne connaît que celle qui est juste en dessous.
Le `TunerBloc` (Présentation) ne fait jamais `import 'dart:isolate'` — l'Isolate
et le protocole de messages sont un détail d'implémentation de `data/`.

---

## 2. Diagramme de séquence — flux complet réel

```
[Musicien]  [UI / Ticker]    [TunerBloc]         [AudioRepositoryImpl]      [Isolate Audio]
    │             │               │                      │                       │
    │             │─(StartTuner)─>│                      │                       │
    │             │               │─(streamPitch(config))>│                       │
    │             │               │  (onListen du Stream) │─Isolate.spawn────────>│
    │             │               │                      │                       │
    │             │               │                      │<──(SendPort, handshake)│
    │             │               │                      │─InitWorkerMessage────>│
    │             │               │                      │                       │
    │             │               │                      │─AudioBufferMessage───>│  (à ~50 Hz,
    │             │               │                      │  (TransferableTypedData)│  TransferableTypedData
    │             │               │                      │                       │   = zéro-copie)
    │             │               │                      │                       │
    │             │               │                      │            [IIR filter (opt.)]
    │             │               │                      │            [YIN detect()]
    │             │               │                      │            [shouldForwardPitch?]
    │             │               │                      │<──PitchDetectedMessage─│
    │             │               │<──Stream<PitchResult>─│                       │
    │             │<─(add PitchReceived → emit TunerListening)                    │
    │  [vsync ×N] │               │                      │                       │
    │  BlocListener met à jour _targetAngle/_targetCents                          │
    │  Ticker interpole (α=0.25) │                        │                       │
    │<─(Canvas)───│               │                      │                       │
```

### Pourquoi ce flux et pas un autre ?

| Décision | Raison |
|---|---|
| `TunerBloc` souscrit à un `Stream<PitchResult>` exposé par `AudioRepository`, jamais au `ReceivePort` directement | Le BLoC ne doit pas connaître l'existence de l'Isolate (détail Data) |
| `AudioRepositoryImpl` est propriétaire de l'`Isolate`/`ReceivePort`/`SendPort` | Il est le seul à spawner et tuer l'Isolate — cycle de vie centralisé, cf. §3.1 |
| `StreamController(onListen: ..., onCancel: ...)` pilote le spawn/kill | Pas de spawn fire-and-forget : l'Isolate n'existe que tant qu'un abonné écoute le stream |
| PCM envoyé du thread principal vers l'Isolate (jamais l'inverse) | Le micro est une ressource plateforme accessible uniquement via plugin Flutter (thread principal) |
| Ticker séparé du flux BLoC | Le flux BLoC arrive à la fréquence du buffer audio (~50 Hz) ; le Ticker tourne au vsync (60/120 Hz) — fréquences et responsabilités différentes |

---

## 3. Détail de chaque couche

### 3.1 Couche Data — `AudioRepositoryImpl` & protocole de messages

Fichiers réels : `data/repositories/audio_repository_impl.dart`,
`data/workers/audio_isolate_worker.dart`.

```
AudioRepositoryImpl implements AudioRepository
│
├── _dataSource : MicrophoneDataSource        ← RecordMicrophoneDataSource (plugin `record`)
├── _isolate : Isolate?
├── _mainPort : ReceivePort?                  ← reçoit SendPort (handshake) + PitchDetectedMessage
├── _workerPort : SendPort?                   ← envoie Init/AudioBuffer/UpdateConfig/Kill
├── _micSubscription : StreamSubscription<Uint8List>?
└── _controller : StreamController<PitchResult>?
```

**Protocole de messages typés** (classes dédiées, pas de `Map` générique) :

| Message | Sens | Contenu |
|---|---|---|
| `InitWorkerMessage` | main → isolate | `TuningConfiguration` initiale |
| `AudioBufferMessage` | main → isolate | `TransferableTypedData` (buffer PCM, transfert zéro-copie) |
| `UpdateConfigMessage` | main → isolate | Nouvelle `TuningConfiguration` (changement de corde, toggle Intelli-Tuner...) |
| `KillWorkerMessage` | main → isolate | Ferme le `ReceivePort` du worker |
| `PitchDetectedMessage` | isolate → main | `PitchResult` calculé |

**Cycle de vie piloté par le `StreamController`** :

```dart
Stream<PitchResult> streamPitch(TuningConfiguration config) {
  _controller = StreamController<PitchResult>(
    onListen: () => _start(config),  // spawn l'Isolate seulement à l'écoute
    onCancel: stop,                   // tue l'Isolate dès la désinscription
  );
  return _controller!.stream;
}
```

`_start()` : `_dataSource.initialize()` (vérifie/demande la permission micro,
lève `AudioPermissionException` si refusée) → `Isolate.spawn(audioIsolateEntryPoint, ...)`
→ handshake (le worker renvoie son `SendPort`) → abonnement au flux PCM du
`MicrophoneDataSource`, chaque chunk étant transmis via
`TransferableTypedData.fromList([chunk])` (transfert mémoire zéro-copie,
important à ~50 Hz sur des buffers de 2048 échantillons).

`stop()`/`_cleanup()` : annule l'abonnement micro, envoie `KillWorkerMessage`,
tue l'Isolate (`Isolate.immediate`), ferme les ports, dispose la datasource,
puis ferme le `StreamController` — idempotent (`_disposed` guard).

---

### 3.2 Couche Data — Isolate Audio (`audioIsolateEntryPoint`)

L'Isolate tourne en isolation complète : pas d'accès à Flutter, pas de widgets,
uniquement `dart:isolate` + calcul pur. Boucle réelle (`_processBuffer`) :

```
1. Reinterpret cast Uint8List → Int16List → normalisation Float64List [-1.0, 1.0]
2. Filtre IIR passe-bande (optionnel — actif uniquement si Intelli-Tuner ON
   ET une corde cible est sélectionnée)
3. YinDetector.detect(samples) → (f0Hz, confidence) ou null
4. shouldForwardPitch(confidence, config) — décide si le résultat remonte (§3.2.1)
5. Conversion Hz → note/octave/cents (référence A4 = referencePitchHz)
6. Détermination du TunerState à partir de l'écart en cents
7. Envoi PitchDetectedMessage(PitchResult) via replyPort
```

**Détection de hauteur — `YinDetector`** : algorithme YIN (différence normalisée
cumulative moyenne + interpolation parabolique autour de τ*), `confidence = 1.0 - cmndf[τ*]`.
Bornes de recherche déduites de `AudioConstants` (`τ_min` ≈ 1200 Hz max,
`τ_max = bufferSize / 2` ≈ 43 Hz min détectable).

**Seuils de `TunerState`** (`_stateFromCents`, réels) :

```
|centsDeviation| ≤ 2.0   →  inTune     (AudioConstants.inTuneThresholdCents)
|centsDeviation| ≤ 5.0   →  nearTune   (AudioConstants.nearTuneThresholdCents)
cents < 0 (au-delà)       →  tooLow
cents > 0 (au-delà)       →  tooHigh
```

> `TunerState.silent` n'est **jamais retourné par le worker** : c'est une
> valeur par défaut côté UI (état initial des widgets `Ticker`, avant toute
> réception de `PitchResult`) — à ne pas confondre avec une détection
> explicite de silence.

#### 3.2.1 `shouldForwardPitch` — filtrage de confiance conditionnel au mode (BUG-01)

```dart
@visibleForTesting
bool shouldForwardPitch(double confidence, TuningConfiguration config) {
  final belowConfidence = confidence < AudioConstants.minConfidence; // 0.85
  return !belowConfidence || config.targetString != null;
}
```

- **Mode AUTO** (`targetString == null`) : une détection sous le seuil de
  confiance est abandonnée — on ne veut pas afficher de note peu fiable.
- **Mode MANUEL** (corde ciblée) : toute détection est transmise, y compris
  sous le seuil — c'est justement le signal qui permet au `TunerBloc`
  d'activer automatiquement l'Intelli-Tuner (cf. §3.4.1). Avant correction, le
  filtrage se faisait inconditionnellement dans l'isolate, ce qui rendait
  l'auto-activation totalement inatteignable (cf. `STRATEGIE_CORRECTION_BOGUES.md`
  BUG-01) — extrait en fonction pure top-level pour être testable sans monter
  d'Isolate ni fabriquer un signal PCM réel à confiance intermédiaire.

#### 3.2.2 Filtre IIR passe-bande — `IirBandpassFilter`

Biquad forme directe II transposée (coefficients *Audio EQ Cookbook*,
Bristow-Johnson), facteur de qualité `Q = 4.0`, centré sur la fréquence
théorique de la corde ciblée (`AudioConstants.stringFrequencies`). Réinitialise
son état interne (`_z1`, `_z2`) à chaque changement de corde cible pour éviter
tout transitoire. Construit/reconstruit uniquement si Intelli-Tuner actif et
une corde est sélectionnée (`_buildFilter`) — sinon `null`, aucun filtrage.

---

### 3.3 Couche Domain — `TuningConfiguration`

Champs réels (`domain/entities/tuning_configuration.dart`) :

```dart
class TuningConfiguration {
  final double referencePitchHz;         // défaut 440.0
  final SweeteningStrategy sweetening;   // déclaré, non exploité (cf. note)
  final List<String> stringNotes;        // ex. ["E2","A2","D3","G3","B3","E4"]
  final String? targetString;            // null = mode AUTO
  final InstrumentType instrumentType;   // guitar | bass | ukulele | custom
  final bool intelliTunerActive;         // pilote le filtre IIR (§3.2.2)
}
```

> **Écart avec la conception d'origine** : `SweeteningStrategy` (`none | railsback
> | guitarCompensated`) existe comme enum mais **n'est consommé nulle part**
> dans le code actuel — aucun UseCase de correction de justesse (courbe de
> Railsback, compensation de sillet) n'a été implémenté. `referencePitchHz`
> est utilisé tel quel, sans ajustement. À considérer comme un axe
> d'évolution future documenté, pas une fonctionnalité livrée.

`TuningConfiguration` reste l'unique point de contact entre l'UI et le
pipeline audio : tout changement (corde, Intelli-Tuner, référence de La...)
passe par un nouvel objet immuable envoyé via `ConfigChanged` (BLoC) puis
`UpdateConfigMessage` (Isolate).

---

### 3.4 Couche Présentation — `TunerBloc` & Ticker

Le BLoC et le Ticker ont des **fréquences de mise à jour différentes** et des
**responsabilités différentes** :

```
Flux BLoC  (~50 Hz, piloté par le signal)    →  émet TunerListening(pitch, config, ...)
Ticker     (60 / 120 Hz, piloté par le vsync) →  interpole l'angle/la position affichée
```

`TunerNeedleWidget` et `CentsBarWidget` sont deux `StatefulWidget` **indépendants**,
chacun avec son propre `Ticker` (`SingleTickerProviderStateMixin`) — pas de
Ticker partagé au niveau de l'écran. Chacun lit la valeur cible via un
`BlocListener<TunerBloc, TunerDisplayState>` dans son `build()` (pas de méthode
publique appelée depuis le BLoC — c'est le widget qui écoute, pas l'inverse) :

```dart
// Extrait réel — tuner_needle_widget.dart
BlocListener<TunerBloc, TunerDisplayState>(
  listener: (_, state) {
    final newTunerState = state is TunerListening ? state.pitch.state : TunerState.silent;
    final newTarget = state is TunerListening
        ? (state.pitch.centsDeviation.clamp(-50.0, 50.0) / 50.0) * (pi / 2)
        : 0.0;
    // setState forcé si l'état fonctionnel change — nécessaire pour la
    // transition inTune → silent quand l'aiguille est déjà centrée
    // (delta ≈ 0, le Ticker ne déclencherait pas setState sans cette garde).
    if (_tunerState != newTunerState) {
      setState(() { _tunerState = newTunerState; _targetAngle = newTarget; });
    } else {
      _targetAngle = newTarget;
    }
  },
  child: RepaintBoundary(child: CustomPaint(painter: _NeedlePainter(...))),
)
```

Le `Ticker` interpole ensuite `_displayAngle` vers `_targetAngle` à chaque
vsync (`alpha = 0.25`, cf. §3.4.2), indépendamment de la fréquence d'arrivée
des `PitchResult`.

#### 3.4.1 Intelli-Tuner — auto-activation (`TunerBloc._onPitchReceived`)

```dart
if (_config.targetString != null &&
    result.confidence < AudioConstants.minConfidence &&
    !_intelliTunerEnabled) {
  _intelliTunerEnabled = true;
  _audioRepository.updateConfig(_config.copyWith(intelliTunerActive: true));
}
```

Ne peut se déclencher que grâce au correctif §3.2.1 (`shouldForwardPitch`) —
sans lui, cette condition n'est jamais atteinte car l'isolate aurait déjà
filtré tout résultat sous le seuil de confiance avant qu'il n'arrive ici.

#### 3.4.2 Pourquoi `alpha = 0.25` et pas 0.1 ou 0.5 ?

```
alpha = 0.10  →  très lissé, lag visible (~200 ms de retard ressenti)
alpha = 0.25  →  réactif, suit bien les variations rapides (~80 ms ressenti) — retenu
alpha = 0.50  →  quasi-instantané, tremble sur les notes instables
alpha = 1.00  →  pas de lissage
```

---

## 4. Gestion du cycle de vie de l'écoute

Le micro doit être coupé (1) quand l'app passe en arrière-plan, **et** (2) dès
que l'utilisateur quitte l'onglet Tuner pour un autre onglet (exigence
vie privée/Green IT, cf. `EXIGENCES_SECURITE.md §1`). Les deux mécanismes sont
**distincts et corrigés séparément** (`STRATEGIE_CORRECTION_BOGUES.md` BUG-02
et BUG-03) — la première version documentée ici (naïve, sur `this.state`)
était boguée ; voici l'implémentation réelle actuelle.

### 4.1 Arrière-plan de l'app — `TunerBloc.didChangeAppLifecycleState`

```dart
bool _wasListeningBeforePause = false;

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _wasListeningBeforePause = this.state is TunerListening; // capturé AVANT StopTuner
    if (!isClosed) add(const StopTuner());
  } else if (state == AppLifecycleState.resumed && _wasListeningBeforePause) {
    _wasListeningBeforePause = false;
    if (!isClosed) add(const StartTuner());
  }
}
```

Point clé : `StopTuner` émet `TunerInitial()`, donc `this.state` n'est plus
`TunerListening` au moment du `resumed` — tester `this.state` directement (comme
dans une version précédente de ce document) est **toujours faux par
construction** et empêche toute reprise. Le flag capturé avant l'émission de
`TunerInitial` est nécessaire.

### 4.2 Visibilité de l'onglet — `MainShell` → `TunerScreen.isActive`

```dart
// main_shell.dart
final screens = [
  TunerScreen(isActive: _currentIndex == 0),
  PresetsScreen(repository: widget.tuningProfileRepository),
  const ChordsScreen(),
];
```

`TunerScreen` (StatefulWidget) construit son propre `TunerBloc` dans
`initState()` (injectable via `blocBuilder` pour les tests) et réagit aux
changements de `isActive` dans `didUpdateWidget` en émettant `StartTuner`/
`StopTuner` — indépendamment du cycle de vie de l'app entière (§4.1). Les deux
mécanismes peuvent se déclencher presque simultanément (ex. double-tap Home,
ou changement d'onglet rapide A→B→A).

### 4.3 Sérialisation `StartTuner`/`StopTuner` — file `_guarded`

`Bloc.on<E>` ne sérialise les événements qu'au sein d'un même type : sans
précaution, `StartTuner` et `StopTuner` peuvent s'exécuter en parallèle et
laisser une souscription micro orpheline (isolate + capture audio actifs
indéfiniment — exactement ce que §4.2 doit empêcher). Une file d'attente
dédiée sérialise les deux types d'événements entre eux :

```dart
Future<void> _lifecycleLock = Future.value();

Future<void> _guarded(Future<void> Function() action) {
  final result = _lifecycleLock.then((_) => isClosed ? null : action());
  _lifecycleLock = result.catchError((_) {});
  return result;
}
```

`_onStart`/`_onStop` passent tous les deux par `_guarded(...)` — garantit
l'ordre `stop → start` même sur un enchaînement rapproché, et revérifie
`isClosed` juste avant exécution (une action mise en file peut se retrouver à
s'exécuter après la fermeture du BLoC, ex. navigation qui démonte le widget
juste après un changement d'onglet).

---

## 5. Diagramme de classes simplifié (réel)

```
Domain
┌─────────────────────┐     ┌───────────────────────┐
│    PitchResult      │     │  TuningConfiguration   │
│─────────────────────│     │───────────────────────│
│ frequencyHz: double │     │ referencePitchHz       │
│ noteName: String    │     │ sweetening (non utilisé)│
│ octave: int         │     │ stringNotes: List      │
│ centsDeviation      │     │ targetString: String?  │
│ confidence: double  │     │ instrumentType         │
│ state: TunerState   │     │ intelliTunerActive     │
└─────────────────────┘     └───────────────────────┘

Data
┌──────────────────────────────────────────────┐
│             AudioRepositoryImpl               │
│──────────────────────────────────────────────│
│ - _isolate, _mainPort, _workerPort            │
│ - _micSubscription, _controller               │
│──────────────────────────────────────────────│
│ + streamPitch(config): Stream<PitchResult>    │
│ + updateConfig(config): Future<void>          │
│ + stop(): Future<void>                        │
└──────────────────────────────────────────────┘

Presentation
┌──────────────────────────────────────────────┐
│                  TunerBloc                    │
│──────────────────────────────────────────────│
│ - _audioRepository, _subscription             │
│ - _wasListeningBeforePause, _lifecycleLock    │
│──────────────────────────────────────────────│
│ on StartTuner / StopTuner (via _guarded)      │
│ on PitchReceived → emit TunerListening        │
│ on ConfigChanged / StringSelected /            │
│    IntelliTunerToggled / PermissionDenied     │
│ didChangeAppLifecycleState (§4.1)             │
└──────────────────────────────────────────────┘
         ↓ TunerListening(pitch, config, ...)
┌──────────────────────────────────────────────┐
│  TunerNeedleWidget / CentsBarWidget           │
│  (StatefulWidget, Ticker indépendant chacun)  │
│──────────────────────────────────────────────│
│ BlocListener → _targetAngle/_targetCents      │
│ Ticker → interpolation (α=0.25) → repaint     │
└──────────────────────────────────────────────┘
```

États réels du BLoC (`sealed class TunerDisplayState`) :
`TunerInitial` · `TunerListening(pitch, config, intelliTunerEnabled)` ·
`TunerPermissionDeniedState(isPermanent)`.

---

## 6. Checklist architecture

- [x] `PitchResult` et `TuningConfiguration` sont dans `domain/entities/` — pas de dépendance Flutter
- [x] `AudioRepository` est une **interface** dans `domain/repositories/` — `AudioRepositoryImpl` dans `data/`
- [x] L'Isolate ne connaît ni Flutter ni aucun widget — messages typés uniquement (`InitWorkerMessage`, etc.)
- [x] Le `TunerBloc` ne fait jamais `import 'dart:isolate'`
- [x] Les ports/l'Isolate sont fermés dans `AudioRepositoryImpl.stop()`/`_cleanup()` — idempotent
- [x] Chaque `Ticker` (`TunerNeedleWidget`, `CentsBarWidget`) est `dispose()`-é dans son `State`
- [x] `StartTuner`/`StopTuner` sont sérialisés entre eux (`_guarded`) — pas de souscription orpheline sur enchaînement rapide (§4.3)
- [x] La reprise après pause se base sur un flag capturé avant `TunerInitial`, pas sur `this.state` au moment du `resumed` (§4.1)
- [x] La visibilité de l'onglet Tuner est découplée du cycle de vie de l'app (`isActive`, §4.2)
- [ ] `SweeteningStrategy` reste déclaré mais non implémenté — ne pas supposer qu'un ajustement Railsback/sillet est appliqué

---

*harmonixTune — ARCHITECTURE_FLUX v2.0 — à jour par rapport au code réel (module Tuner, post BUG-01/02/03)*
