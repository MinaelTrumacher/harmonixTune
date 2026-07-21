# harmonixTune — Cahier de recettes

> Périmètre recetté : **V1 Monophonique** (accordeur seul — cf. `harmonixTune_project_response_ideas.md`, phase 1.3).
> Les onglets **Presets** et **Chords** sont hors périmètre : ce sont des écrans stub non fonctionnels
> (V2/V3), ils ne font l'objet d'aucun scénario ci-dessous.
> Référence : `DEV_STRATEGY.md` · `ARCHITECTURE_FLUX.md` · `AUDIT_PRE_MERGE.md` / `AUDIT_POST_FIX.md`

---

## 1. Objectif

Ce document définit les scénarios de test fonctionnels à exécuter manuellement (ou via
`integration_test`) avant toute mise en production, afin de détecter les anomalies et
régressions **du point de vue utilisateur** — en complément des tests unitaires (`test/`)
qui valident la logique interne (BLoC, algorithmes, repository) mais pas l'expérience
réelle sur device.

## 2. Environnement de test

| Élément | Valeur |
|---|---|
| Devices cibles | Smartphone Android (physique, micro requis) + iOS si disponible |
| Mode de build | `flutter run --release` (le mode debug désactive Crashlytics/Performance et affiche le slider de debug qui n'existe pas en prod) |
| Conditions audio | Environnement calme + environnement bruyant (télé/conversation en fond) |
| Instrument | Guitare accordée standard (E2 A2 D3 G3 B3 E4) — cf. `AudioConstants.stringFrequencies` |
| Seuils de référence | In tune : ≤ ±2 cents · Near tune : ≤ ±5 cents · Confiance minimale : 0.85 · Fréquence min. détectable : ≈ 43 Hz |

## 3. Convention

Chaque scénario suit le format : **ID · Préconditions · Étapes · Résultat attendu · Statut**.

Statut à remplir lors de l'exécution : ✅ OK · ❌ KO (renvoie vers un ticket dans
`docs/PLAN_CORRECTION_BOGUES.md`) · ⏭️ Non exécuté.

---

## 4. Scénarios — Permissions microphone

### PERM-01 — Premier lancement, permission accordée

- **Préconditions** : app fraîchement installée, permission micro jamais demandée
- **Étapes** : lancer l'app → accepter la demande de permission système
- **Résultat attendu** : l'écran Tuner s'affiche directement en écoute (aiguille active), pas d'écran de blocage
- **Statut** : ✅ OK

### PERM-02 — Refus simple de la permission

- **Préconditions** : app fraîchement installée
- **Étapes** : lancer l'app → refuser la demande de permission système
- **Résultat attendu** : écran "Accès au microphone requis" avec bouton **Réessayer** ; aucun crash
- **Statut** : ❌ KO — voir `docs/PLAN_CORRECTION_BOGUES.md#BUG-02`. Rejoué après révocation de la permission via Réglages Android (donc app mise en pause) : au retour, l'écran Tuner s'affiche normalement mais sans activité (aiguille inactive, aucune détection) — l'écran de blocage attendu n'apparaît jamais

### PERM-03 — Réessayer après refus simple

- **Préconditions** : état PERM-02 atteint
- **Étapes** : appuyer sur **Réessayer** → accepter la permission cette fois
- **Résultat attendu** : retour à l'écran Tuner en écoute active
- **Statut** : ❌ KO — voir `docs/PLAN_CORRECTION_BOGUES.md#BUG-02`. Même symptôme que PERM-02 : impossible d'atteindre l'écran "Réessayer" puisque l'écran de blocage ne s'affiche jamais après un passage par les réglages système

### PERM-04 — Refus définitif ("Ne plus demander")

- **Préconditions** : refuser la permission avec l'option "Ne plus demander" (Android) ou refuser deux fois (iOS)
- **Étapes** : relancer l'app
- **Résultat attendu** : écran de blocage affiche le bouton **Ouvrir les réglages** (et non "Réessayer") ; le bouton ouvre bien les réglages système de l'app
- **Statut** : ❌ KO — voir `docs/PLAN_CORRECTION_BOGUES.md#BUG-02`. Aucun écran de blocage affiché donc aucun bouton "Ouvrir les réglages" disponible dans l'app

### PERM-05 — Activation depuis les réglages système

- **Préconditions** : état PERM-04, réglages système ouverts
- **Étapes** : activer la permission micro dans les réglages → revenir sur l'app (résumé)
- **Résultat attendu** : l'app détecte le changement au retour au premier plan et repasse en écoute active (pas besoin de relancer l'app)
- **Statut** : ✅ OK (constaté) — mais résultat à interpréter avec prudence : compte tenu de `BUG-02` (le retour au premier plan ne redéclenche l'écoute que si l'état sauvegardé était déjà `TunerListening`, jamais depuis `TunerInitial`), ce succès est probablement dû à un redémarrage complet du process Android suite au changement de permission (comportement plateforme, pas garanti sur toutes versions/constructeurs) plutôt qu'à une reprise correcte gérée par le code. Ne pas considérer ce scénario comme une preuve que le cycle de vie est correctement géré — cf. `docs/PLAN_CORRECTION_BOGUES.md#BUG-02`

---

## 5. Scénarios — Détection de note et affichage

### TUN-01 — Silence / pas de signal

- **Préconditions** : app en écoute, permission accordée
- **Étapes** : ne rien jouer, environnement calme
- **Résultat attendu** : aucune fausse détection, aiguille reste au repos / état "silent"
- **Statut** : ✅ OK

### TUN-02 — Note juste (in tune)

- **Étapes** : jouer une corde à vide correctement accordée (ex. La 220 Hz sur A2)
- **Résultat attendu** : aiguille centrée, barre de cents affiche **"✓ IN TUNE"** en vert, écart ≤ ±2 cents
- **Statut** : ✅ OK

### TUN-03 — Note légèrement désaccordée (near tune)

- **Étapes** : désaccorder très légèrement une corde (3 à 5 cents d'écart)
- **Résultat attendu** : état visuel "ambre"/near-tune, écart affiché en cents (pas "IN TUNE")
- **Statut** : ✅ OK

### TUN-04 — Note trop basse / trop haute

- **Étapes** : désaccorder franchement une corde (> 10 cents) dans chaque sens
- **Résultat attendu** : aiguille penche clairement à gauche (trop bas) ou à droite (trop haut), couleur d'état cohérente (bleu/rouge selon la charte `UI_DESIGN.md`)
- **Statut** : ✅ OK

### TUN-05 — Nom de note et fréquence affichés

- **Étapes** : jouer successivement E2, A2, D3, G3, B3, E4
- **Résultat attendu** : le nom de note affiché correspond à la corde jouée à chaque fois, la fréquence en Hz est cohérente (± quelques Hz)
- **Statut** : ✅ OK

### TUN-06 — Limite basse de détection (~43 Hz)

- **Étapes** : jouer une note proche de la limite théorique basse (E2 = 82 Hz reste largement au-dessus, donc tester avec un instrument grave si disponible, ex. corde de basse détendue)
- **Résultat attendu** : pas de comportement erratique (pas de note aléatoire affichée) en dessous de la limite ; en dessous de ~43 Hz l'app doit rester en "silent" plutôt que d'afficher une fausse note
- **Statut** : ✅ OK — testé avec la corde de Mi grave (E1 ≈ 41 Hz) d'une basse : non détectée, mais aucune fausse note affichée (comportement conforme, la fréquence est sous le seuil théorique de ~43 Hz)

### TUN-07 — Robustesse au bruit ambiant

- **Préconditions** : bruit de fond (conversation, musique en sourdine)
- **Étapes** : jouer une note pendant que le bruit est présent
- **Résultat attendu** : la détection reste stable sur la note jouée, pas de saut erratique vers une fausse fréquence
- **Statut** : ✅ OK — testé avec musique forte (ambiance de stade) au casque + basse jouée à distance : détection stable sur la basse, aucun déclenchement sur le bruit de foule

---

## 6. Scénarios — Sélecteur de cordes et Intelli-Tuner

### STR-01 — Mode AUTO par défaut

- **Étapes** : lancer l'app, ne sélectionner aucune corde
- **Résultat attendu** : aucune corde n'apparaît sélectionnée, l'app détecte n'importe quelle corde jouée
- **Statut** : ✅ OK

### STR-02 — Sélection manuelle d'une corde

- **Étapes** : appuyer sur une corde (ex. "D3") dans le sélecteur
- **Résultat attendu** : la corde sélectionnée est visuellement mise en avant, les autres passent en opacité réduite
- **Statut** : ✅ OK

### STR-03 — Retour au mode AUTO

- **Préconditions** : état STR-02
- **Étapes** : appuyer à nouveau sur la corde sélectionnée
- **Résultat attendu** : retour au mode AUTO (plus aucune corde en surbrillance)
- **Statut** : ✅ OK

### ITN-01 — Auto-activation de l'Intelli-Tuner (filtre passe-bande)

- **Préconditions** : corde sélectionnée manuellement (ex. STR-02)
- **Étapes** : jouer un signal à faible confiance de détection (ex. pincer très légèrement la corde, ou jouer avec du bruit de fond important)
- **Résultat attendu** : le toggle Intelli-Tuner passe automatiquement à l'état actif dès que la confiance descend sous 0.85 ; le filtre stabilise la détection sur la corde ciblée
- **Statut** : ❌ KO — voir `docs/PLAN_CORRECTION_BOGUES.md#ITN-01`. Le toggle Intelli-Tuner est un bouton manuel dans l'IHM ; aucune auto-activation observée quand la confiance chute, contrairement au comportement attendu

### ITN-02 — Activation manuelle du toggle Intelli-Tuner

- **Étapes** : activer manuellement le toggle Intelli-Tuner (sans attendre l'auto-activation)
- **Résultat attendu** : le toggle passe actif immédiatement, la config est répercutée sans coupure perceptible de la détection
- **Statut** : ✅ OK

### ITN-03 — Désélection de corde désactive l'Intelli-Tuner

- **Préconditions** : état ITN-01 ou ITN-02 (Intelli-Tuner actif, corde sélectionnée)
- **Étapes** : repasser en mode AUTO (STR-03)
- **Résultat attendu** : l'Intelli-Tuner se désactive automatiquement, cohérent avec le mode AUTO
- **Statut** : ✅ OK

---

## 7. Scénarios — Cycle de vie de l'application

### LIFE-01 — Mise en arrière-plan pendant l'écoute

- **Préconditions** : app en écoute active
- **Étapes** : appuyer sur le bouton Accueil / passer à une autre app
- **Résultat attendu** : le micro et le traitement audio s'arrêtent (vérifiable via l'indicateur micro système Android/iOS qui doit disparaître) — cf. exigence Green IT de `harmonixTune_project_response_ideas.md`
- **Statut** : ✅ OK

### LIFE-02 — Retour au premier plan

- **Préconditions** : état LIFE-01
- **Étapes** : revenir sur l'app
- **Résultat attendu** : l'écoute reprend automatiquement sans action utilisateur, sans crash, avec la configuration précédente (corde sélectionnée, Intelli-Tuner) conservée
- **Statut** : ❌ KO — voir `docs/PLAN_CORRECTION_BOGUES.md#LIFE-02`. Au retour au premier plan, plus aucune détection de son ; seul un redémarrage complet de l'app (kill + relance) rétablit l'écoute

### LIFE-03 — Appel téléphonique entrant pendant l'écoute (Android/iOS)

- **Étapes** : recevoir un appel pendant que l'app écoute
- **Résultat attendu** : l'app libère proprement le micro pendant l'appel, reprend l'écoute normalement après ; pas de crash
- **Statut** : ⏭️ Non exécuté (à tester)

### LIFE-04 — Rotation d'écran

- **Étapes** : faire pivoter le device
- **Résultat attendu** : l'orientation reste verrouillée en portrait (comportement voulu, cf. `SystemChrome.setPreferredOrientations` dans `main.dart`), pas de glitch visuel
- **Statut** : ✅ OK

---

## 8. Scénarios — Navigation

### NAV-01 — Changement d'onglet

- **Étapes** : naviguer Tuner → Presets → Chords → Tuner
- **Résultat attendu** : navigation instantanée (`IndexedStack`, pas de rebuild), l'état de l'écran Tuner (corde sélectionnée, Intelli-Tuner) est conservé au retour
- **Statut** : ✅ OK

### NAV-02 — Écoute interrompue en quittant l'onglet Tuner

- **Étapes** : depuis l'écran Tuner en écoute, basculer sur l'onglet Presets
- **Résultat attendu** : *(à valider — comportement actuel non garanti par le code revu : `IndexedStack` garde le widget monté, donc l'écoute pourrait continuer en arrière-plan sur un autre onglet)* → si l'écoute continue hors de l'onglet Tuner, considérer comme anomalie Green IT à consigner
- **Statut** : ❌ KO — voir `docs/PLAN_CORRECTION_BOGUES.md#NAV-02`. Confirmé : en jouant une note depuis l'onglet Presets, la nouvelle note est bien affichée au retour sur l'onglet Tuner → l'écoute micro continue en arrière-plan hors de l'onglet Tuner (anomalie Green IT)

---

## 9. Scénarios — Non-régression (à rejouer à chaque version)

| ID | Résumé | Lien |
|---|---|---|
| REG-01 | Rejouer PERM-01 à PERM-05 | Non-régression permissions |
| REG-02 | Rejouer TUN-02 à TUN-05 sur les 6 cordes standard | Non-régression détection |
| REG-03 | Rejouer ITN-01 à ITN-03 | Non-régression Intelli-Tuner (cf. F-01 `AUDIT_PRE_MERGE.md` — bug déjà corrigé, à surveiller en cas de régression) |
| REG-04 | Rejouer LIFE-01/LIFE-02 | Non-régression cycle de vie / fuite micro |

---

## 10. Hors périmètre connu (à consigner, pas à recetter maintenant)

- **Accessibilité** (lecteur d'écran, contraste, taille de police système) : non couverte par ce cahier, aucun `Semantics` identifié dans le code à ce jour — gap à traiter séparément (compétence "développer le logiciel").
- **Presets / Chords** : écrans stub, non fonctionnels.
- **iOS** : `GoogleService-Info.plist` non généré à ce jour (cf. `MONITORING_SETUP.md` §5) — recette iOS complète impossible tant que ce point n'est pas résolu.

---

## 11. Synthèse d'exécution

| Catégorie | Nb scénarios | ✅ OK | ❌ KO | ⏭️ Non exécuté |
|---|---|---|---|---|
| Permissions | 5 | 2 | 3 | 0 |
| Détection/affichage | 7 | 7 | 0 | 0 |
| Sélecteur de cordes / Intelli-Tuner | 6 | 5 | 1 | 0 |
| Cycle de vie | 4 | 2 | 1 | 1 |
| Navigation | 2 | 1 | 1 | 0 |
| **Total** | **24** | **17** | **6** | **1** |

**Critère de sortie (go/no-go release)** : 0 anomalie bloquante (PERM-*, LIFE-01/02, TUN-01/02)
non résolue. Les anomalies non bloquantes sont reportées dans
`docs/PLAN_CORRECTION_BOGUES.md`.

**Statut actuel : NO-GO.** `docs/PLAN_CORRECTION_BOGUES.md#BUG-02` (LIFE-02, bloquant) est la
cause racine de **4 des 6 KO** de cette session (LIFE-02, PERM-02, PERM-03, PERM-04) : quitter
l'app pour les réglages système la met en pause, et le retour au premier plan ne relance jamais
l'écoute ni la demande de permission tant que l'état sauvegardé n'était pas déjà `TunerListening`.
C'est donc l'anomalie prioritaire à corriger — elle bloque à elle seule la moitié du périmètre
Permissions et le critère de sortie LIFE-01/02. ITN-01 et NAV-02 restent également ouverts mais
non listés comme bloquants ci-dessus ; à confirmer avec le porteur de projet si leur portée
justifie de les traiter comme tels avant release. LIFE-03 (appel entrant) reste à rejouer.

---

*harmonixTune — CAHIER_DE_RECETTES v1.0 — Périmètre V1 Monophonique*
