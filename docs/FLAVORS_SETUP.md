# harmonixTune — Mise en place des flavors dev/staging/prod

> Périmètre : séparation Android en 3 environnements de build (dev/staging/prod),
> partie "environnements de déploiement" du bloc de compétences.
> Décision prise : **un seul projet Firebase partagé** (`harmonixtune-e6964`) pour
> les 3 flavors — pas d'isolation complète des données de crash/perf par
> environnement pour l'instant (cf. échange avec l'utilisateur).
> Référence : `MONITORING_SETUP.md`

---

## 1. Ce qui a été mis en place côté Dart

| Fichier | Rôle |
|---|---|
| `lib/core/config/flavor.dart` | `enum Flavor { dev, staging, prod }` + `FlavorConfig` (holder statique du flavor courant) |
| `lib/bootstrap.dart` | Logique d'init commune (Hive, Firebase, Crashlytics, Performance, `runZonedGuarded`), paramétrée par `Flavor` |
| `lib/main_dev.dart` | Entrypoint : `bootstrap(Flavor.dev)` |
| `lib/main_staging.dart` | Entrypoint : `bootstrap(Flavor.staging)` |
| `lib/main_prod.dart` | Entrypoint : `bootstrap(Flavor.prod)` |
| `lib/main.dart` | Alias de confort → `bootstrap(Flavor.prod)`, pour que `flutter run` sans `-t` reste utilisable |

Les 3 environnements partagent 100% du code applicatif — seul `Flavor.flavor`
(fixé une fois au démarrage) et l'`applicationId` Android diffèrent.

## 2. Ce qui a été mis en place côté Android

`android/app/build.gradle.kts` — `productFlavors` sur la dimension `environment` :

| Flavor | applicationId | Nom affiché |
|---|---|---|
| dev | `com.example.harmonix_tune.dev` | harmonixTune Dev |
| staging | `com.example.harmonix_tune.staging` | harmonixTune Staging |
| prod | `com.example.harmonix_tune` (inchangé) | harmonixTune |

`prod` garde l'`applicationId` d'origine : c'est celui déjà enregistré dans
Firebase et celui qui ira sur le Store. `dev`/`staging` ont un suffixe pour
pouvoir être installés côte à côte avec `prod` sur le même téléphone.

`AndroidManifest.xml` : `android:label` pointe maintenant sur `@string/app_name`
(généré par flavor via `resValue`) au lieu du nom en dur `"harmonix_tune"`.

## 3. Commandes de lancement / build

```powershell
# Lancer un flavor en dev
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor prod -t lib/main_prod.dart

# Builder un APK release
flutter build apk --release --flavor staging -t lib/main_staging.dart
```

> À partir du moment où des `productFlavors` existent, Android **exige**
> `--flavor` sur toute commande `flutter run`/`flutter build` — un `flutter run`
> sans argument échouera désormais côté Android tant que le flavor n'est pas
> précisé (ou géré via une config de lancement IDE dédiée par flavor).

## 4. Incident rencontré et corrigé pendant la mise en place : conflit `record_linux`

En testant le premier build (`flutter build apk --flavor prod --debug`), la
compilation échouait **avant même d'atteindre Gradle**, avec cette erreur :

```
Error: The non-abstract class 'RecordLinux' is missing implementations for
these members: RecordMethodChannelPlatformInterface.startStream
```

**Diagnostic** : `record: 5.2.1` (résolu par le solveur de dépendances) tire
`record_platform_interface: 1.6.0`, mais le paquet transitif `record_linux`
restait bloqué en `0.7.2` — une version qui n'implémente pas l'interface 1.6.0.
C'est une incohérence dans la matrice de versions publiée par le paquet
`record` lui-même (plugin fédéré), sans lien avec les flavors : elle aurait
cassé n'importe quel `flutter build`/`flutter test` dès qu'un `flutter pub get`
aurait re-résolu les dépendances vers cette combinaison.

Le Linux desktop n'est pas une cible réelle de l'app (mobile uniquement), mais
le compilateur Dart inclut quand même `record_linux.dart` dans le kernel
snapshot lors de la compilation, quelle que soit la plateforme cible — d'où
l'échec même en buildant pour Android.

**Correctif appliqué** — override ciblé dans `pubspec.yaml` :

```yaml
dependency_overrides:
  record_linux: ^1.0.0
```

Résolu en pratique vers `record_linux 1.3.1`, compatible avec
`record_platform_interface 1.6.0` et le SDK Dart installé (3.10.7 — les
versions `record_linux >= 2.1.0` exigent Dart `>=3.12.0`, indisponible ici).

**Piste explicitement écartée** : monter `record` en v7.x (qui a une matrice
de versions cohérente) aurait été le correctif "propre", mais c'est un saut de
version majeure avec API potentiellement différente sur un paquet au cœur du
pipeline audio temps réel (`record_microphone_data_source.dart`) — trop risqué
pour être fait à l'aveugle dans le cadre de cette tâche. À reconsidérer
séparément, avec revue du changelog `record` 5→7 et tests dédiés.

**Vérification** : `flutter build apk --flavor prod --debug -t lib/main_prod.dart`
compile et produit `app-prod-debug.apk`.

## 5. Ce qu'il reste à faire

### ✅ Résolu — enregistrement Firebase dev/staging (Android)

`flutterfire configure` (CLI 1.4.0) **n'a pas détecté les `productFlavors`
Gradle automatiquement** — elle s'est contentée de ré-enregistrer l'app `prod`
déjà existante, sans proposer `dev`/`staging`. La détection auto de flavors
n'est donc pas fiable avec cette version de la CLI.

**Correctif appliqué** : enregistrement manuel des 2 apps Android manquantes
directement dans la console Firebase (Paramètres du projet → Général → Vos
applications → Ajouter une application), avec les package names
`com.example.harmonix_tune.dev` et `com.example.harmonix_tune.staging`. Le
`google-services.json` téléchargé après le 2ᵉ enregistrement contient bien les
3 clients (prod + dev + staging) et a remplacé `android/app/google-services.json`.

App IDs Firebase obtenus :

| Flavor | Package | App ID |
|---|---|---|
| prod | `com.example.harmonix_tune` | `1:111449505542:android:9d39de28a2f70aaaada887` |
| dev | `com.example.harmonix_tune.dev` | `1:111449505542:android:75961272a61e87e6ada887` |
| staging | `com.example.harmonix_tune.staging` | `1:111449505542:android:b12a6491e5ca16abada887` |

**Vérifié** : les 3 flavors compilent (`app-dev-debug.apk`, `app-staging-debug.apk`,
`app-prod-debug.apk`). Le job `deploy_beta` dans `dart.yml` utilise désormais
le bon App ID staging.

**Limite connue** : `lib/firebase_options.dart` reste généré pour l'app `prod`
uniquement (la CLI ne gère qu'un seul jeu d'options par plateforme). Les
builds dev/staging utilisent donc les mêmes `FirebaseOptions` que prod pour
l'initialisation Dart-side — sans conséquence sur le fonctionnement (le
`google-services.json` multi-clients suffit à faire fonctionner Crashlytics/
Performance nativement selon l'`applicationId` réel de chaque build), mais les
événements remontés depuis dev/staging apparaîtront dans le dashboard Firebase
sous l'entrée "prod" plutôt que sous des entrées distinctes. À revoir
uniquement si des dashboards séparés par environnement deviennent nécessaires.

### Non traité dans ce chantier

- **iOS** : pas de schémas Xcode par flavor (nécessite un Mac — cf.
  `MONITORING_SETUP.md` pour le même blocage sur `GoogleService-Info.plist`).
- **CI `quality_gate`** : ne build pas d'APK (seulement `flutter analyze` +
  `flutter test`), donc pas impactée par les flavors.
- **Isolation Firebase complète par environnement** : décision prise de
  rester sur un projet partagé pour l'instant (cf. §0).

---

*harmonixTune — FLAVORS_SETUP v1.0 — dev/staging/prod (Android)*
