# harmonixTune — Exigences de sécurité du prototype

> Complète `UI_DESIGN.md` / `DEV_STRATEGY.md` : ces documents couvrent l'ergonomie
> et l'architecture du prototype mais ne formalisaient pas d'exigences de
> sécurité — c'est l'objet de ce document.
> Référentiel utilisé : OWASP Mobile Top 10 (grille de lecture, pas une
> certification) + RGPD (l'app ne cible pas de public professionnel soumis à
> d'autres référentiels).
> Chaque exigence est évaluée par rapport à l'état réel du code (audité le
> 21/07/2026), pas par rapport à des intentions.

---

## 1. Permissions et vie privée (microphone)

| Exigence | Statut | Détail |
|---|---|---|
| Déclarer la permission micro sur chaque plateforme | ✅ Conforme | Android : héritée automatiquement du manifeste du plugin `record_android` (fusion Gradle, pas de déclaration manuelle nécessaire). iOS : **`NSMicrophoneUsageDescription` était absente de `ios/Runner/Info.plist`** — corrigé dans ce chantier (sans elle, iOS tue l'app au premier accès micro, sans message d'erreur exploitable). |
| Ne jamais accéder au micro sans demande explicite | ✅ Conforme | `RecordMicrophoneDataSource.initialize()` vérifie `Permission.microphone.status` puis `.request()` avant tout accès (`record_microphone_data_source.dart:24-35`). |
| Couper le micro dès que l'app n'est plus au premier plan | ✅ Conforme (corrigé dans ce chantier) | `BUG-02`/`BUG-03` (`PLAN_CORRECTION_BOGUES.md`, correctifs détaillés dans `STRATEGIE_CORRECTION_BOGUES.md`) : `TunerScreen` reçoit désormais l'index d'onglet actif depuis `MainShell` et déclenche `StopTuner`/`StartTuner` sur `TunerBloc` en conséquence (`tuner_screen.dart`) ; le micro ne tourne donc plus une fois l'onglet Tuner quitté. Vérifié par tests automatisés (`tuner_screen_test.dart`, `tuner_bloc_test.dart`) ; **recette manuelle sur device réel (NAV-02) pas encore rejouée** — à faire avant de considérer le point definitivement clos. |
| Ne jamais enregistrer ni transmettre l'audio capté | ✅ Conforme par construction | Le flux PCM ne quitte jamais l'Isolate local (`audio_isolate_worker.dart`) : aucun appel réseau, aucune écriture disque du buffer audio brut. À rester vigilant : ne jamais ajouter de log (`debugPrint`, Crashlytics custom key) qui inclurait un échantillon audio brut. |
| Informer clairement l'utilisateur pourquoi le micro est nécessaire | ✅ Conforme | `_PermissionDeniedView` (`tuner_screen.dart`) explique l'usage avant de proposer Réessayer/Réglages ; description iOS ajoutée dans ce chantier reprend la même justification. |

## 2. Stockage local (profils d'accordage — Hive)

| Exigence | Statut | Détail |
|---|---|---|
| Ne stocker aucune donnée personnelle identifiante | ✅ Conforme | `TuningProfile` (nom de profil choisi par l'utilisateur, type d'instrument, liste de cordes) — aucune donnée de compte, aucun identifiant, aucune donnée de localisation. |
| Chiffrement au repos | ⚪ Non requis pour l'instant | La box Hive (`tuning_profiles`) est ouverte sans `encryptionCipher`. Décision : pas de PII stockée → pas de chiffrement nécessaire aujourd'hui. À revoir si une fonctionnalité future stocke des données plus sensibles (ex. compte utilisateur). |
| Isolation des données par utilisateur si le stockage devient partagé | ⚪ Sans objet | Pas de synchronisation cloud ni de compte multi-utilisateur en V1/V2. |

## 3. Télémétrie (Crashlytics / Performance)

| Exigence | Statut | Détail |
|---|---|---|
| Aucune donnée personnelle ou audio dans les rapports de crash | ✅ Conforme (vérifié) | `bootstrap.dart` n'attache aucune clé custom (`setCustomKey`) ni log manuel — seuls les rapports de crash Flutter/Dart standards de Crashlytics sont envoyés. Recherche de code confirmée : aucun `debugPrint`/`log` de données sensibles dans `lib/`. |
| Désactivation en développement | ✅ Conforme | `setCrashlyticsCollectionEnabled(!kDebugMode)` et `setPerformanceCollectionEnabled(!kDebugMode)` — pas de pollution du dashboard par les sessions de dev. |
| Information de l'utilisateur sur la télémétrie | 🔴 **Non traité** | Aucune mention de Crashlytics/Performance dans l'app (pas de politique de confidentialité affichée, pas d'écran de consentement). Actuellement sans conséquence RGPD forte (pas de donnée personnelle collectée), mais à traiter avant publication sur les stores : Apple/Google exigent une politique de confidentialité déclarée même pour de la télémétrie technique anonyme. |

## 4. Build et distribution

| Exigence | Statut | Détail |
|---|---|---|
| Signature de release dédiée (pas les clés de debug) | 🔴 **Non conforme** | `android/app/build.gradle.kts:41-44` : `signingConfig = signingConfigs.getByName("debug")` pour le buildType `release`, avec commentaire `TODO` d'origine template Flutter jamais traité. Sans conséquence pour la distribution beta (Firebase App Distribution, cf. `MONITORING_SETUP.md`), **bloquant avant tout envoi sur le Play Store** (Google impose une signature de release propre, gérée idéalement via Play App Signing). |
| Obfuscation / minification du code de release | 🔴 **Non fait** | Pas de `isMinifyEnabled`/`isShrinkResources`/règles ProGuard dans `build.gradle.kts`. Risque faible pour cette app (pas de secret métier critique dans le code), mais standard de durcissement recommandé avant publication — réduit aussi la taille de l'APK. |
| Pas de secret en clair dans le dépôt | ✅ Conforme | `google-services.json`/`firebase_options.dart` sont des identifiants client publics (non secrets par design Firebase, cf. `MONITORING_SETUP.md`). Aucune clé API tierce, mot de passe ou token trouvé dans `lib/`. |
| Mise à jour des dépendances suivie | 🟡 Partiel | Pas de `dependabot.yml`/Renovate configuré malgré la mention dans `harmonixTune_project_response_ideas.md` (Phase 3, veille). L'incident `record_linux` (cf. `FLAVORS_SETUP.md §4`) montre concrètement le risque d'une résolution de dépendances non surveillée. |

## 5. Synthèse et priorités

| Priorité | Exigence non conforme | Action |
|---|---|---|
| 🔴 Haute | Micro actif hors de l'onglet Tuner (§1) | **Corrigé dans ce chantier** (`BUG-03`, `tuner_screen.dart`/`main_shell.dart`) — recette manuelle NAV-02 sur device réel restant à rejouer pour clôture définitive. |
| 🔴 Haute | `NSMicrophoneUsageDescription` absente | **Corrigé dans ce chantier** (`ios/Runner/Info.plist`). |
| 🟠 Avant publication store | Signature de release sur clés debug | Générer un keystore de release dédié + configurer `signingConfig` (Play App Signing recommandé). |
| 🟠 Avant publication store | Pas d'obfuscation | Activer `isMinifyEnabled`/ProGuard sur le buildType release. |
| 🟠 Avant publication store | Pas de politique de confidentialité affichée | Rédiger et lier une politique de confidentialité (Crashlytics/Performance) — exigée par les stores. |
| 🟡 Amélioration continue | Pas de suivi automatisé des dépendances | Ajouter `dependabot.yml` (GitHub) pour Dart/Gradle. |

---

*harmonixTune — EXIGENCES_SECURITE v1.1*
