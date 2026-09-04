# harmonixTune — Mise en place du monitoring (Crashlytics + Performance)

> Périmètre : intégration de Firebase Crashlytics et Firebase Performance dans l'app.
> S'inscrit dans le bloc de compétences "Mettre en œuvre des environnements de déploiement
> et de test en y intégrant les outils de suivi de performance et de qualité".
> Référence : `DEV_STRATEGY.md` · `ARCHITECTURE_FLUX.md`

---

## 1. Objectif

Avant cette intégration, l'app ne disposait d'aucun retour sur son comportement en dehors
du poste de développement : un crash chez un utilisateur (bruit ambiant inattendu, device
non testé, permission micro refusée dans un état imprévu...) n'aurait laissé aucune trace
exploitable.

Firebase Crashlytics remonte les crashs et erreurs non gérées avec la stack trace complète.
Firebase Performance mesure les temps de démarrage, la fluidité et les traces custom
(pertinent ici pour surveiller la latence du pipeline audio en conditions réelles).

---

## 2. Projet Firebase

- **Projet** : `harmonixtune-e6964`
- **Plateformes enregistrées** : `android` (`com.example.harmonix_tune`), `ios` (`com.example.harmonixTune`)
- Généré via la CLI officielle `flutterfire configure --project=harmonixtune-e6964`

---

## 3. Outils installés (poste de dev)

| Outil | Commande d'installation | Rôle |
|---|---|---|
| Node.js / npm | déjà présent | pré-requis pour `firebase-tools` |
| Firebase CLI | `npm.cmd install -g firebase-tools` | authentification (`firebase login`) et gestion du projet Firebase |
| FlutterFire CLI | `dart pub global activate flutterfire_cli` | génère `firebase_options.dart` et enregistre les apps sur le projet Firebase |

> **Note Windows** : la politique d'exécution PowerShell par défaut bloque les scripts
> `.ps1` non signés (`npm.ps1`, `firebase.ps1`). Solution utilisée : appeler les
> exécutables via leur alias `.cmd` (`npm.cmd`, `firebase.cmd`) plutôt que de modifier
> `Set-ExecutionPolicy`. Le binaire `flutterfire.bat` installé par `dart pub global
> activate` doit aussi être ajouté au `PATH` utilisateur
> (`%LOCALAPPDATA%\Pub\Cache\bin`), absent par défaut sur Windows.

---

## 4. Dépendances ajoutées (`pubspec.yaml`)

```yaml
dependencies:
  firebase_core: ^4.12.1
  firebase_crashlytics: ^5.2.6
  firebase_performance: ^0.11.4+5
```

Installées via `flutter pub add firebase_core firebase_crashlytics firebase_performance`.

---

## 5. Fichiers générés par `flutterfire configure`

| Fichier | Rôle |
|---|---|
| `lib/firebase_options.dart` | Configuration Firebase par plateforme (`DefaultFirebaseOptions.currentPlatform`), généré automatiquement — ne pas éditer à la main |
| `android/app/google-services.json` | Identifiants client Android, requis par le plugin Gradle `google-services` |
| `firebase.json` | Mapping des apps FlutterFire pour la CLI |

Ces fichiers **ne sont pas des secrets** : ce sont des identifiants client publics,
déjà embarqués dans le binaire de l'app. Ils sont committés dans le repo.

> iOS : `GoogleService-Info.plist` n'a pas été généré (pas de build iOS possible depuis
> ce poste Windows). À régénérer via `flutterfire configure` depuis un Mac avant le
> premier build iOS.

### Modifications Android (automatiques)

`android/settings.gradle.kts` — déclaration des plugins Gradle :

```kotlin
plugins {
    id("com.google.gms.google-services") version("4.4.4") apply false
    id("com.google.firebase.firebase-perf") version("2.0.2") apply false
    id("com.google.firebase.crashlytics") version("3.0.7") apply false
}
```

`android/app/build.gradle.kts` — application des plugins :

```kotlin
plugins {
    id("com.google.gms.google-services")
    id("com.google.firebase.firebase-perf")
    id("com.google.firebase.crashlytics")
}
```

---

## 6. Initialisation dans `lib/main.dart`

```dart
Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(!kDebugMode);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      runApp(const HarmonixTuneApp());
    },
    (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
  );
}
```

**Points clés :**

- `runZonedGuarded` capte les erreurs asynchrones qui échapperaient à `FlutterError.onError`
  (ex. exception dans un `Future` non attendu).
- `FlutterError.onError` capte les erreurs de rendu/framework Flutter (ex. exception dans
  un `build()`).
- `PlatformDispatcher.instance.onError` capte les erreurs Dart pures hors framework Flutter
  (ex. dans un `Isolate` non géré séparément).
- Collecte désactivée en mode debug (`!kDebugMode`) pour ne pas polluer le dashboard avec
  les crashs provoqués volontairement pendant le développement.

---

## 7. Vérification effectuée

```
flutter analyze --fatal-warnings --fatal-infos   →  No issues found!
flutter test                                      →  117/117 tests passés
```

Aucune régression sur la suite de tests existante (le `widget_test.dart` instancie
`HarmonixTuneApp` directement sans passer par `main()`, donc pas de dépendance à
Firebase dans les tests).

---

## 8. Comment vérifier que la remontée fonctionne réellement

1. Ajouter temporairement un déclencheur de crash :
   ```dart
   ElevatedButton(
     onPressed: () => FirebaseCrashlytics.instance.crash(),
     child: const Text('Test Crash'),
   )
   ```
2. Lancer l'app en mode release : `flutter run --release` (la collecte est désactivée
   en debug, cf. section 6).
3. Déclencher le crash, puis relabelliser l'app pour forcer l'envoi du rapport en file
   d'attente.
4. Vérifier l'apparition du rapport dans la console Firebase → Crashlytics (délai de
   quelques minutes).
5. Retirer le bouton de test avant de merger.

---

## 9. Fichiers modifiés / créés dans cette intégration

```
M  android/app/build.gradle.kts
M  android/settings.gradle.kts
M  lib/main.dart
M  pubspec.yaml / pubspec.lock
+  android/app/google-services.json
+  firebase.json
+  lib/firebase_options.dart
+  docs/MONITORING_SETUP.md
```

---

## 10. Ce qu'il reste à faire (suite du bloc de compétences)

| Élément | Statut |
|---|---|
| Crashlytics + Performance (Android) | ✅ Fait |
| Config iOS (`GoogleService-Info.plist`) | ⏳ À faire depuis un Mac |
| Suivi de couverture de tests (Codecov) | ⏳ À faire — prochaine étape |
| Environnements dev/staging/prod (flavors) | ⏳ Non démarré |
| Traces de performance custom sur le pipeline audio | ⏳ Non démarré (Performance auto-instrumente déjà démarrage/écrans) |

---

*harmonixTune — MONITORING_SETUP v1.0 — Intégration Firebase Crashlytics & Performance*
