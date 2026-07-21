# harmonixTune — Architecture & Flux de Données

> **Périmètre de ce document** : Flux de données audio de bout en bout, contrats entre couches,
> et mécanique de rendu UI temps réel. Complémentaire de `UI_DESIGN.md`.

---

## 1. Vue d'ensemble des couches (Clean Architecture)

```
┌─────────────────────────────────────────────────────────┐
│  PRESENTATION                                           │
│  TunerScreen · TunerBLoC · Ticker · CustomPainter      │
├─────────────────────────────────────────────────────────┤
│  DOMAIN                                                 │
│  PitchResult · TuningConfiguration · PitchDetectionUseCase │
├─────────────────────────────────────────────────────────┤
│  DATA                                                   │
│  AudioRepository · MicrophoneDataSource · Isolate Audio │
└─────────────────────────────────────────────────────────┘
```

**Règle stricte** : une couche ne connaît que celle qui est juste en dessous.
Le BLoC (Présentation) ne touche jamais ni à l'Isolate ni au `ReceivePort` — ce sont
des détails d'implémentation de la couche Data.

---

## 2. Diagramme de séquence corrigé — Flux complet

```
[Musicien]  [UI / Ticker]    [TunerBLoC]       [AudioRepository]     [Isolate Audio]
    │             │               │                    │                     │
    │─(Joue)─────>│               │                    │                     │
    │             │               │                    │                     │
    │             │─(StartTuner)─>│                    │                     │
    │             │               │                    │                     │
    │             │               │─(streamPitch())───>│                     │
    │             │               │  ←subscribe        │─(SpawnIsolate)─────>│
    │             │               │   Stream<PitchResult>                    │
    │             │               │                    │<──[ReceivePort]──────│
    │             │               │                    │                     │
    │             │               │                    │══(buffers PCM)═════>│
    │             │               │                    │                     │
    │             │               │                    │    [Calcul YIN]     │
    │             │               │                    │    (Hz, cents)      │
    │             │               │                    │<──(PitchResult)─────│
    │             │               │                    │                     │
    │             │               │<──Stream<PitchResult>───────────────────  │
    │             │<─(targetAngle)│                    │                     │
    │             │               │                    │                     │
    │  [vsync ×N] │               │                    │                     │
    │  _angle=lerp│               │                    │                     │
    │<─(Canvas)───│               │                    │                     │
```

### Pourquoi ce flux et pas un autre ?

| Décision | Raison |
|---|---|
| BLoC souscrit à un `Stream<PitchResult>`, pas au Port direct | Le BLoC ne doit pas connaître l'existence de l'Isolate (détail Data) |
| `AudioRepository` est propriétaire du `ReceivePort` | Il est le seul à spawner et tuer l'Isolate — cycle de vie centralisé |
| PCM envoyé de Repository vers Isolate (et non l'inverse) | Le micro est une ressource du thread principal ; l'Isolate ne peut pas l'ouvrir directement sans passer par un plugin Flutter |
| Ticker séparé du stream BLoC | Le stream BLoC arrive à ~50 Hz (audio) ; le Ticker tourne à 60/120 Hz (vsync) — fréquences différentes, responsabilités différentes |

---

## 3. Détail de chaque couche

### 3.1 Couche Data — AudioRepository & Isolate

```
AudioRepository
│
├── MicrophoneDataSource          ← ouvre le flux PCM via plugin Flutter
│   └── Stream<Uint8List>         ← buffers PCM bruts
│
├── _isolate : Isolate            ← spawné à la demande
├── _sendPort : SendPort          ← envoie les buffers à l'Isolate
└── _receivePort : ReceivePort    ← reçoit les PitchResult de l'Isolate
    └── Stream<PitchResult>       ← exposé vers le Domain/BLoC
```

**Séquence interne au démarrage :**

```dart
// À l'intérieur d'AudioRepository.streamPitch()

// 1. Ouvrir le micro → obtenir un Stream<Uint8List> de buffers PCM
final pcmStream = await _micSource.open(sampleRate: 44100, bufferSize: 2048);

// 2. Spawner l'Isolate en lui passant le SendPort pour la réponse
_receivePort = ReceivePort();
_isolate = await Isolate.spawn(
  _audioIsolateEntryPoint,
  _AudioIsolateConfig(
    replyPort: _receivePort.sendPort,
    tuningConfig: currentConfig,
  ),
);

// 3. Récupérer le SendPort de l'Isolate (premier message)
_sendPort = await _receivePort.first as SendPort;

// 4. Brancher le flux PCM → Isolate
pcmStream.listen((buffer) => _sendPort.send(buffer));

// 5. Exposer le flux de résultats vers le haut
return _receivePort
    .skip(1) // skip le handshake SendPort
    .whereType<PitchResult>();
```

**Point critique — transfert zéro-copie :**
Les buffers PCM sont envoyés via `TransferableTypedData` (et non une `List<int>` classique)
pour éviter la copie mémoire entre threads. Sur un buffer de 2048 échantillons × 4 octets = 8 Ko
à ~50 Hz, ça représente 400 Ko/s de copie économisée.

```dart
_sendPort.send(TransferableTypedData.fromList([buffer]));
```

---

### 3.2 Couche Data — Isolate Audio (thread secondaire)

L'Isolate tourne en isolation complète : pas d'accès à Flutter, pas de widgets.
Il reçoit des buffers, calcule, renvoie des résultats.

```
[Isolate Audio — boucle principale]

  ┌─────────────────────────────────────────────┐
  │  1. Recevoir buffer PCM (Int16List)          │
  │  2. Appliquer filtre passe-bas (optionnel)   │
  │  3. Appliquer filtre Intelli-Tuner           │
  │     (passe-bande autour de la corde cible)   │
  │  4. Algorithme YIN sur la fenêtre            │
  │     → fréquence fondamentale en Hz           │
  │  5. Convertir Hz → note + cents d'écart      │
  │     (en tenant compte de TuningConfiguration)│
  │  6. Envoyer PitchResult via SendPort         │
  └─────────────────────────────────────────────┘
```

**Entité PitchResult (Domain) :**

```dart
class PitchResult {
  final double frequencyHz;    // fréquence brute détectée
  final String noteName;       // ex. "E"
  final int octave;            // ex. 4
  final double centsDeviation; // ex. -2.3 (négatif = grave)
  final double confidence;     // 0.0 → 1.0 (fiabilité de la détection YIN)
  final TunerState state;      // silent | tooLow | inTune | tooHigh
}
```

**Seuils de TunerState :**

```
|centsDeviation| > 5   →  tooLow / tooHigh
|centsDeviation| ≤ 5   →  presque juste (ambre)
|centsDeviation| ≤ 2   →  inTune (vert)
confidence < 0.85       →  silent (pas de note détectée)
```

---

### 3.3 Couche Domain — TuningConfiguration & Strategy Pattern

```dart
// Entité immuable transmise du BLoC → UseCase → Isolate
class TuningConfiguration {
  final double referencePitchHz;       // défaut : 440.0
  final SweeteningStrategy sweetening; // none | railsback | guitarCompensated
  final List<String> stringNotes;      // ex. ["E2","A2","D3","G3","B3","E4"]
  final String? targetString;          // null = mode AUTO
}

enum SweeteningStrategy { none, railsback, guitarCompensated }
```

Le UseCase calcule `targetHz` pour la note détectée selon la stratégie :

```
none              → targetHz = 440.0 × 2^((midiNote - 69) / 12)
railsback         → targetHz corrigé par la courbe de Railsback (table de lookup)
guitarCompensated → targetHz ajusté par les coefficients de compensation de sillet
```

C'est ici que le **Strategy Pattern** s'applique : interchanger `SweeteningStrategy`
ne touche ni au BLoC ni à l'Isolate. Seul le UseCase connaît les stratégies.

---

### 3.4 Couche Présentation — BLoC & Ticker (la séparation clé)

Le BLoC et le Ticker ont des **fréquences de mise à jour différentes** et des
**responsabilités différentes**. Les confondre est la source de tous les problèmes
d'animation audio.

```
Flux BLoC  (~50 Hz, piloté par le signal)    →  met à jour targetAngle
Ticker     (60 / 120 Hz, piloté par le vsync) →  interpole _angle vers targetAngle
```

```dart
class _TunerNeedleState extends State<TunerNeedleWidget>
    with SingleTickerProviderStateMixin {

  late final Ticker _ticker;
  double _displayAngle = 0.0;      // angle actuellement dessiné
  double _targetAngle = 0.0;       // angle cible, mis à jour par le BLoC

  static const double _alpha = 0.25; // facteur de lissage (0 = immobile, 1 = instantané)

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      // Appelé à chaque vsync — interpole sans durée fixe
      final next = _displayAngle + _alpha * (_targetAngle - _displayAngle);
      if ((next - _displayAngle).abs() > 0.0001) {
        setState(() => _displayAngle = next);
      }
    })..start();
  }

  // Appelé depuis le BLoC (hors vsync, à la fréquence audio)
  void updateTarget(double centsDeviation) {
    _targetAngle = (centsDeviation / 50.0) * (pi / 2);
    // Pas de setState ici — le Ticker s'en charge au prochain frame
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
```

**Pourquoi `alpha = 0.25` et pas 0.1 ou 0.5 ?**

```
alpha = 0.10  →  très lissé, lag visible (~200 ms de retard ressenti)
alpha = 0.25  →  réactif, suit bien les variations rapides (~80 ms ressenti)
alpha = 0.50  →  quasi-instantané, tremble sur les notes instables
alpha = 1.00  →  pas de lissage (équivaut à AnimationController durée 0)
```

0.25 est le bon compromis pour un accordeur : réactif sans tremblement sur les cordes
qui ne sont pas encore stables. Ajustable en settings avancés si nécessaire.

---

## 4. Gestion du cycle de vie — quand couper le micro

Le micro doit être **coupé dès que l'app passe en arrière-plan**. C'est une exigence
Green IT (batterie) et une exigence de confidentialité (RGPD).

```
AppLifecycleState.resumed   → AudioRepository.start()  → Isolate spawné
AppLifecycleState.paused    → AudioRepository.stop()   → Isolate tué, micro fermé
AppLifecycleState.detached  → AudioRepository.dispose() → nettoyage complet
```

Le BLoC écoute `AppLifecycleState` via `WidgetsBindingObserver` et émet les
événements `StartTunerEvent` / `StopTunerEvent` en conséquence.

```dart
// Dans TunerBLoC
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) add(StopTunerEvent());
  if (state == AppLifecycleState.resumed) add(StartTunerEvent());
}
```

---

## 5. Diagramme de classes simplifié

```
Domain
┌─────────────────────┐     ┌──────────────────────┐
│    PitchResult      │     │  TuningConfiguration  │
│─────────────────────│     │──────────────────────│
│ frequencyHz: double │     │ referencePitchHz      │
│ noteName: String    │     │ sweetening: Strategy  │
│ octave: int         │     │ stringNotes: List     │
│ centsDeviation      │     │ targetString: String? │
│ confidence: double  │     └──────────────────────┘
│ state: TunerState   │
└─────────────────────┘

Data
┌──────────────────────────────────────────────┐
│               AudioRepository                │
│──────────────────────────────────────────────│
│ - _isolate: Isolate                          │
│ - _sendPort: SendPort                        │
│ - _receivePort: ReceivePort                  │
│──────────────────────────────────────────────│
│ + streamPitch(config): Stream<PitchResult>   │
│ + updateConfig(config): void                 │
│ + stop(): Future<void>                       │
└──────────────────────────────────────────────┘

Presentation
┌──────────────────────────────────────────────┐
│                 TunerBLoC                    │
│──────────────────────────────────────────────│
│ - _repo: AudioRepository                     │
│ - _subscription: StreamSubscription          │
│──────────────────────────────────────────────│
│ + on StartTunerEvent → subscribe stream      │
│ + on StopTunerEvent  → cancel subscription   │
│ + on ConfigChanged   → repo.updateConfig()   │
│ → emit TunerState (targetAngle, note, Hz)    │
└──────────────────────────────────────────────┘
         ↓ targetAngle (hors vsync)
┌──────────────────────────────────────────────┐
│          TunerNeedleWidget (StatefulWidget)  │
│──────────────────────────────────────────────│
│ - _ticker: Ticker (vsync)                    │
│ - _displayAngle: double                      │
│ - _targetAngle: double                       │
│──────────────────────────────────────────────│
│ Ticker: _displayAngle = lerp(α=0.25)         │
│ Painter: NeedlePainter(_displayAngle)        │
└──────────────────────────────────────────────┘
```

---

## 6. Checklist architecture avant de coder

- [ ] `PitchResult` et `TuningConfiguration` sont dans `domain/entities/` — pas de dépendance Flutter
- [ ] `AudioRepository` est une **interface** dans `domain/repositories/` — l'implémentation est dans `data/`
- [ ] L'Isolate ne connaît ni Flutter ni aucun widget — il ne reçoit que des `List<int>` et renvoie des `Map`
- [ ] Le BLoC ne fait jamais `import 'dart:isolate'` — ce détail est encapsulé dans `data/`
- [ ] Le `ReceivePort` est fermé dans `AudioRepository.stop()` — pas de fuite mémoire
- [ ] Le `Ticker` est `dispose()`-é dans le State — pas de fuite mémoire
- [ ] `TuningConfiguration` est l'unique point de contact entre UI et algorithme — tout changement de paramètre passe par là

---

*Document généré pour harmonixTune — Version Architecture v0.1*
*Prochaine étape : implémenter `AudioRepository` + `PitchResult` (Phase Data-1)*
