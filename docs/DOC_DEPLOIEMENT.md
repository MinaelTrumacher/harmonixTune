# harmonixTune — Documentation de déploiement et d'exploitation

> Décrit **comment builder, déployer et exploiter** l'application au
> quotidien : environnements, CI/CD, secrets, monitoring, procédure de
> release et gestion des incidents. Synthétise et relie `MONITORING_SETUP.md`,
> `FLAVORS_SETUP.md` et `EXIGENCES_SECURITE.md` — se référer à ces documents
> pour le détail de chaque chantier.

---

## 1. Prérequis

| Outil / compte | Usage |
|---|---|
| Flutter SDK (channel stable) | Build de l'app |
| Compte GitHub avec accès au repo `MinaelTrumacher/harmonixTune` | Code source, CI/CD, Actions |
| Compte Firebase (projet `harmonixtune-e6964`) | Crashlytics, Performance, App Distribution |
| Compte Codecov lié au repo GitHub | Suivi de la couverture de tests |
| Firebase CLI + FlutterFire CLI (poste de dev uniquement) | Régénérer `firebase_options.dart`/`google-services.json` si de nouvelles apps sont enregistrées |
| macOS + Xcode (non disponible actuellement) | Build/signature iOS — non fait dans ce projet, cf. `MONITORING_SETUP.md §5` |

## 2. Environnements (flavors)

3 environnements Android, même code Dart, `applicationId` distinct :

| Flavor | `applicationId` | Usage |
|---|---|---|
| `dev` | `com.example.harmonix_tune.dev` | Développement local, installable à côté de staging/prod |
| `staging` | `com.example.harmonix_tune.staging` | Build distribué aux testeurs (beta) |
| `prod` | `com.example.harmonix_tune` | Version destinée au Store (signature à finaliser, cf. §7) |

Commandes de lancement/build (détail complet : `FLAVORS_SETUP.md`) :

```powershell
flutter run --flavor dev -t lib/main_dev.dart
flutter run --release --flavor staging -t lib/main_staging.dart
flutter build apk --release --flavor prod -t lib/main_prod.dart
```

> Depuis l'ajout des flavors, `--flavor` est **obligatoire** sur toute
> commande `flutter run`/`flutter build` Android — un lancement sans flavor
> échoue (Gradle n'a plus de variante "nue").

## 3. Pipeline CI/CD

Fichier : `.github/workflows/dart.yml`. 2 jobs :

### 3.1 `quality_gate` — à chaque push/PR sur `develop`/`master`

1. `flutter pub get`
2. `dart run build_runner build` (génère les adaptateurs Hive)
3. `dart format --set-exit-if-changed .`
4. `flutter analyze --fatal-warnings --fatal-infos`
5. `flutter test --coverage`
6. Upload de la couverture sur Codecov

Ce job est **bloquant** : des rulesets GitHub sur `develop` et `master`
exigent que `quality_gate` réussisse avant de pouvoir merger une PR.

### 3.2 `deploy_beta` — uniquement sur push direct vers `develop`, si `quality_gate` a réussi

1. Build de l'APK release, flavor `staging`
2. Upload vers Firebase App Distribution, groupe de testeurs `testers`

**Résultat concret** : tout merge sur `develop` qui passe la CI part
automatiquement en beta chez les testeurs enregistrés — c'est le mécanisme de
déploiement progressif du projet.

### 3.3 Secrets GitHub Actions requis

| Secret | Rôle |
|---|---|
| `CODECOV_TOKEN` | Upload du rapport de couverture |
| `FIREBASE_SERVICE_ACCOUNT` | Authentification (compte de service JSON, rôle *Firebase App Distribution Admin*) pour l'upload vers App Distribution |

Configurés dans `Settings → Secrets and variables → Actions` du repo GitHub.

## 4. Firebase — projet et apps enregistrées

Projet unique `harmonixtune-e6964`, partagé par les 3 flavors (décision :
pas d'isolation complète des données de crash/perf par environnement, cf.
`FLAVORS_SETUP.md §0`).

| Flavor | App ID Firebase |
|---|---|
| prod | `1:111449505542:android:9d39de28a2f70aaaada887` |
| dev | `1:111449505542:android:75961272a61e87e6ada887` |
| staging | `1:111449505542:android:b12a6491e5ca16abada887` |

`android/app/google-services.json` contient les 3 clients (un par
`applicationId`) — c'est ce fichier qui permet à Gradle de résoudre
automatiquement la bonne config selon le flavor buildé. `lib/firebase_options.dart`
reste en revanche généré pour le flavor `prod` uniquement (limite connue,
sans impact fonctionnel — cf. `FLAVORS_SETUP.md §5`).

**Ajouter un testeur** : console Firebase → projet → App Distribution →
Testeurs et groupes → groupe `testers` → ajouter l'email du testeur.

## 5. Monitoring en production

- **Crashlytics** : console Firebase → projet → Crashlytics — liste des
  crashs remontés, groupés par signature, avec stack trace complète.
  Collecte désactivée en mode debug (`kDebugMode`), donc uniquement les
  sessions release/beta/prod remontent des données.
- **Performance** : console Firebase → projet → Performance — temps de
  démarrage, traces automatiques par écran.
- Aucune donnée personnelle ni audio n'est jamais transmise (cf.
  `EXIGENCES_SECURITE.md §3`).

## 6. Procédure de release

```
feature/xxx → PR → develop   (quality_gate doit passer)
                     │
                     └─→ deploy_beta déclenché automatiquement
                          → build staging → Firebase App Distribution
                          → testeurs notifiés, installent/mettent à jour l'app

develop → master  (une fois la beta validée par les testeurs)
```

> **État actuel** : il n'existe pas encore de job CI de publication vers le
> Play Store/App Store depuis `master` — la signature de release n'est pas
> finalisée (cf. §7) et la publication store n'a pas encore été engagée. Le
> merge vers `master` sert aujourd'hui de point de bascule "version stable
> validée", sans automatisation de publication au-delà.

## 7. Ce qui bloque encore une publication sur les stores (hors périmètre actuel)

Détaillé dans `EXIGENCES_SECURITE.md §4` :

- Signature de release Android sur clés **debug** (template Flutter jamais
  remplacé) — générer un keystore de release dédié avant tout envoi Play
  Store.
- Pas d'obfuscation (`isMinifyEnabled`) activée sur le buildType release.
- Pas de politique de confidentialité affichée dans l'app (exigée par les
  stores même pour de la télémétrie technique anonyme).
- Build/signature iOS jamais réalisés (nécessite macOS + Xcode).

## 8. Gestion des incidents

1. **Un crash remonte sur Crashlytics** : identifier la version/flavor
   concernée (visible dans le rapport), consulter la stack trace.
2. **Correctif** : traiter comme un bug classique — cf. méthode déjà
   appliquée dans `PLAN_CORRECTION_BOGUES.md`/`STRATEGIE_CORRECTION_BOGUES.md`
   (constat → cause racine → correctif ciblé → tests → recette).
3. **Rollback** : pas de mécanisme de rollback automatisé (pas de
   publication store active à ce jour) — en cas de régression détectée après
   un merge sur `develop`, revenir en arrière se fait par un revert Git
   classique suivi d'un nouveau push (redéclenche `quality_gate` +
   `deploy_beta` sur la version corrigée).

## 9. Documents de référence

| Document | Contenu |
|---|---|
| `MONITORING_SETUP.md` | Détail pas-à-pas de l'intégration Firebase Crashlytics/Performance |
| `FLAVORS_SETUP.md` | Détail de la mise en place des flavors et de l'incident `record_linux` |
| `EXIGENCES_SECURITE.md` | Exigences de sécurité formalisées et statut de conformité |
| `CAHIER_DE_RECETTES.md` | Scénarios de non-régression à rejouer avant chaque release |

---

*harmonixTune — DOC_DEPLOIEMENT v1.0*
