# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce
fichier.

Le format s'appuie sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et ce projet adhère au [Semantic Versioning](https://semver.org/lang/fr/)
(`MAJEUR.MINEUR.CORRECTIF+numéroDeBuild`).

## [Non publié]

_Rien en attente — dernière version livrée : 1.2.0._

## [1.2.0] - 2026-07-21

### Ajouté
- Environnements `dev` / `staging` / `prod` (flavors Android), points
  d'entrée Dart dédiés (`main_dev.dart`, `main_staging.dart`,
  `main_prod.dart`) et `applicationId` distincts par environnement.
- Pipeline de déploiement continu `deploy_beta` : build automatique de
  l'APK release (flavor `staging`) et publication sur Firebase App
  Distribution à chaque push sur `develop` ayant passé la porte de
  qualité (`quality_gate`).

### Corrigé
- **BUG-02** — perte de la détection audio après une mise en arrière-plan
  de l'application puis un retour au premier plan (seul un redémarrage
  complet rétablissait l'écoute). Cause : le flag d'état interne utilisé
  pour décider de relancer l'écoute était écrasé avant d'être testé
  (`tuner_bloc.dart`).
- **BUG-03** — le microphone restait actif en arrière-plan lors de la
  navigation vers un onglet autre que Tuner, du fait du montage permanent
  des écrans par `IndexedStack` (`main_shell.dart`, `tuner_screen.dart`).
- **BUG-01** — le mode Intelli-Tuner ne s'activait jamais automatiquement
  en mode manuel sur un signal à faible confiance : le filtrage de
  confiance appliqué dans l'isolate audio empêchait la condition
  d'auto-activation du BLoC de s'exécuter (`audio_isolate_worker.dart`).

### Tests
- Ajout de tests `bloc_test` couvrant le cycle de vie de l'application
  (arrêt manuel puis pause, permission révoquée pendant la pause, pause
  pendant le mode debug).
- Ajout de tests widget sur la gestion de visibilité d'onglet (montage
  initial vs. transitions `isActive`).
- Extraction et test unitaire dédié de la fonction pure
  `shouldForwardPitch`.

## [1.1.0] - 2026-07-20

### Ajouté
- Intégration de Firebase Crashlytics et Firebase Performance
  (supervision des crashs et des performances applicatives).
- Intégration de Codecov : publication automatique de la couverture de
  tests à chaque exécution de la CI.

### Corrigé
- Alignement du workflow CI sur la branche `master` (au lieu de `main`).

## [1.0.0] - 2026-07-20

### Ajouté
- Accordeur monophonique fonctionnel : pipeline audio réel (microphone
  → Isolate → algorithme YIN), remplaçant le flux mocké de la phase UI
  initiale.
- Gestion des profils d'accordage (onglet Presets, persistance Hive).
- Mise en place de l'intégration continue (GitHub Actions) : formatage,
  analyse statique stricte, exécution des tests unitaires.

[Non publié]: https://github.com/MinaelTrumacher/harmonixTune/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/MinaelTrumacher/harmonixTune/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/MinaelTrumacher/harmonixTune/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/MinaelTrumacher/harmonixTune/releases/tag/v1.0.0
