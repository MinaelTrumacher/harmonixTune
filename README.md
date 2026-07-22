# harmonixTune

[![HarmonixTune CI](https://github.com/MinaelTrumacher/harmonixTune/actions/workflows/dart.yml/badge.svg)](https://github.com/MinaelTrumacher/harmonixTune/actions/workflows/dart.yml)
[![codecov](https://codecov.io/gh/MinaelTrumacher/harmonixTune/graph/badge.svg)](https://codecov.io/gh/MinaelTrumacher/harmonixTune)

Accordeur d'instruments à cordes (guitare, basse, ukulélé) en Flutter — détection
de hauteur en temps réel, robuste au bruit ambiant, sans publicité.

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Stack technique](#stack-technique)
- [Architecture](#architecture)
- [Démarrage](#démarrage)
- [Environnements (flavors)](#environnements-flavors)
- [Tests et qualité](#tests-et-qualité)
- [CI/CD](#cicd)
- [Structure du projet](#structure-du-projet)
- [Documentation](#documentation)

## Fonctionnalités

| Module | Statut | Détail |
|---|---|---|
| **Tuner** | ✅ Fonctionnel | Détection monophonique temps réel (algorithme YIN), mode AUTO ou corde ciblée, Intelli-Tuner (filtre passe-bande auto-activé sur signal bruité), aiguille + barre de cents animées |
| **Presets** | ✅ Fonctionnel | Profils d'accordage personnalisés (nom, instrument, cordes), persistés localement (Hive), hors connexion |
| **Chords** | 🚧 Conception terminée, non codé | Reconnaissance d'accords polyphonique (STFT + chromagramme) — spécification prête dans `docs/UC_03_strategy.md` |

Contexte produit complet (parties prenantes, périmètre MVP, SWOT) :
[`docs/harmonixTune_project_response_ideas.md`](docs/harmonixTune_project_response_ideas.md).

## Stack technique

| | |
|---|---|
| Framework | Flutter / Dart |
| État | `flutter_bloc` (BLoC) |
| Persistance | Hive |
| Télémétrie | Firebase Crashlytics + Performance |
| Traitement audio | Isolate Dart dédié (YIN, filtre IIR) |
| Tests | `flutter_test`, `bloc_test`, `mocktail` |
| CI/CD | GitHub Actions + Firebase App Distribution + Codecov |

## Architecture

Clean Architecture à 3 couches (`domain` / `data` / `presentation`), dépendance
à sens unique, chaque composant injecté par constructeur (pas de service
locator). Détail complet, choix justifiés et diagrammes de flux :
[`docs/DOC_REALISATION.md`](docs/DOC_REALISATION.md) ·
[`docs/ARCHITECTURE_FLUX.md`](docs/ARCHITECTURE_FLUX.md).

## Démarrage

### Prérequis

- Flutter SDK (channel stable) — `flutter --version`
- Un device/émulateur Android (ou iOS, cf. limitations ci-dessous)

### Installation

```bash
git clone https://github.com/MinaelTrumacher/harmonixTune.git
cd harmonixTune
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # adaptateurs Hive
```

### Lancer l'application

L'app utilise des **flavors** (dev/staging/prod) — `--flavor` et `-t` sont
obligatoires sur toute commande Android :

```bash
flutter run --flavor dev -t lib/main_dev.dart
```

> Plateformes : Android supporté et testé. iOS déclaré au niveau code
> (permission microphone incluse) mais jamais buildé/testé sur device réel
> dans ce projet (nécessite un poste macOS + Xcode).

## Environnements (flavors)

| Flavor | `applicationId` | Usage |
|---|---|---|
| `dev` | `com.example.harmonix_tune.dev` | Développement local |
| `staging` | `com.example.harmonix_tune.staging` | Distribution beta (Firebase App Distribution) |
| `prod` | `com.example.harmonix_tune` | Version stable — signature de release à finaliser avant publication store |

Détail de la mise en place : [`docs/FLAVORS_SETUP.md`](docs/FLAVORS_SETUP.md).

## Tests et qualité

```bash
flutter analyze --fatal-warnings --fatal-infos
flutter test --coverage
```

226 tests automatisés, 88.6% de couverture de lignes (badge Codecov ci-dessus).
Scénarios de recette manuelle (non-régression fonctionnelle) :
[`docs/CAHIER_DE_RECETTES.md`](docs/CAHIER_DE_RECETTES.md).

## CI/CD

GitHub Actions (`.github/workflows/dart.yml`) :

- **`quality_gate`** (push/PR sur `develop`/`master`) : format, analyse
  statique, tests + couverture. Bloquant — requis par les rulesets de
  protection de branche.
- **`deploy_beta`** (push sur `develop`, si `quality_gate` passe) : build
  release flavor `staging`, distribution automatique aux testeurs via
  Firebase App Distribution.

Procédure de release complète, gestion des secrets, monitoring en production :
[`docs/DOC_DEPLOIEMENT.md`](docs/DOC_DEPLOIEMENT.md).

## Structure du projet

```
lib/
├── main.dart / main_dev.dart / main_staging.dart / main_prod.dart
├── bootstrap.dart        ← init partagée (Hive, Firebase)
├── core/                 ← config flavors, constantes, utilitaires
├── domain/                ← entités, interfaces, validateurs (pur Dart)
├── data/                  ← implémentations, Isolate audio, persistance Hive
└── presentation/           ← écrans, BLoC, thème

test/                      ← miroir de lib/, 226 tests
docs/                       ← documentation complète (cf. ci-dessous)
```

## Documentation

| Document | Contenu |
|---|---|
| [`DOC_REALISATION.md`](docs/DOC_REALISATION.md) | Architecture, choix techniques, structure du code |
| [`DOC_UTILISATION.md`](docs/DOC_UTILISATION.md) | Guide utilisateur, écran par écran |
| [`DOC_DEPLOIEMENT.md`](docs/DOC_DEPLOIEMENT.md) | Environnements, CI/CD, secrets, monitoring, procédure de release |
| [`ARCHITECTURE_FLUX.md`](docs/ARCHITECTURE_FLUX.md) | Flux de données audio de bout en bout |
| [`MONITORING_SETUP.md`](docs/MONITORING_SETUP.md) | Intégration Firebase Crashlytics/Performance |
| [`FLAVORS_SETUP.md`](docs/FLAVORS_SETUP.md) | Mise en place des environnements dev/staging/prod |
| [`EXIGENCES_SECURITE.md`](docs/EXIGENCES_SECURITE.md) | Exigences de sécurité et statut de conformité |
| [`CAHIER_DE_RECETTES.md`](docs/CAHIER_DE_RECETTES.md) | Scénarios de test fonctionnels |
| [`PLAN_CORRECTION_BOGUES.md`](docs/PLAN_CORRECTION_BOGUES.md) | Anomalies détectées en recette |
| [`STRATEGIE_CORRECTION_BOGUES.md`](docs/STRATEGIE_CORRECTION_BOGUES.md) | Correctifs appliqués et testés |
| [`DEV_STRATEGY.md`](docs/DEV_STRATEGY.md) / [`DEVLOG.md`](docs/DEVLOG.md) | Phases de construction de l'UI et décisions associées |
| [`UC_01_strategy.md`](docs/UC_01_strategy.md) / [`UC_02_strategy.md`](docs/UC_02_strategy.md) / [`UC_03_strategy.md`](docs/UC_03_strategy.md) | Spécifications techniques par cas d'utilisation |
| [`UI_DESIGN.md`](docs/UI_DESIGN.md) | Design system et maquettes |
| [`harmonixTune_project_response_ideas.md`](docs/harmonixTune_project_response_ideas.md) | Cadrage projet (parties prenantes, périmètre, SWOT) |
