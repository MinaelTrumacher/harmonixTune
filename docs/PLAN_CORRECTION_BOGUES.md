# harmonixTune — Plan de correction des bogues

> Référence : `CAHIER_DE_RECETTES.md` (session d'exécution du 21/07/2026).
> Ce document consigne les anomalies remontées en ❌ KO lors de la recette V1
> Monophonique, avec cause racine identifiée dans le code et piste de
> correction. Aucun correctif n'a encore été appliqué — ce document sert de
> base de décision avant intervention.

---

## Synthèse

| ID | Scénario(s) recette | Bloquant release ? | Statut |
|---|---|---|---|
| [BUG-01](#bug-01--itn-01--intelli-tuner-ne-sactive-jamais-automatiquement) | ITN-01 | À confirmer (fonctionnalité clé "Intelli-Tuner" non opérante en auto) | 🔴 Ouvert |
| [BUG-02](#bug-02--life-02--lécoute-ne-reprend-jamais-après-un-retour-au-premier-plan) | **LIFE-02, PERM-02, PERM-03, PERM-04** | **Oui** — LIFE-01/02 est dans le périmètre bloquant explicite de `CAHIER_DE_RECETTES.md` §11, et cause à elle seule 4 des 6 anomalies de la session | 🔴 Ouvert — **priorité 1** |
| [BUG-03](#bug-03--nav-02--le-micro-continue-découter-en-dehors-de-longlet-tuner) | NAV-02 | À confirmer (impact Green IT / vie privée perçue, pas de crash) | 🔴 Ouvert |

Reste à rejouer (non exécuté en session, hors périmètre de ce plan) : LIFE-03
— voir `CAHIER_DE_RECETTES.md`.

**Note PERM-05** : rejoué OK, mais ce succès est probablement dû à un
redémarrage complet du process Android déclenché par le changement de
permission (comportement plateforme, non garanti), pas à une reprise gérée
correctement par le code — voir la mise en garde dans `CAHIER_DE_RECETTES.md`.
Une fois BUG-02 corrigé, PERM-05 devra être rejoué pour confirmer qu'il passe
aussi pour la bonne raison.

---

## BUG-01 · ITN-01 — L'Intelli-Tuner ne s'active jamais automatiquement

**Constat recette** : en mode manuel (corde sélectionnée) avec un signal à
faible confiance, le toggle Intelli-Tuner reste inactif. Seule l'activation
manuelle (ITN-02) fonctionne.

**Cause racine** : le filtrage par confiance est fait deux fois, à deux
niveaux différents, et le premier empêche le second de jamais se déclencher.

1. Dans l'isolate audio, `audio_isolate_worker.dart:109` :
   ```dart
   if (detected == null || detected.confidence < AudioConstants.minConfidence) {
     return;
   }
   ```
   Tout résultat de détection avec `confidence < 0.85` est **abandonné avant
   même d'être renvoyé** à l'isolate principal — aucun message n'est envoyé
   sur `replyPort`.

2. Dans le BLoC, `tuner_bloc.dart:77-82` :
   ```dart
   if (_config.targetString != null &&
       result.confidence < AudioConstants.minConfidence &&
       !_intelliTunerEnabled) {
     _intelliTunerEnabled = true;
     ...
   }
   ```
   Cette logique d'auto-activation ne peut recevoir que des `PitchResult` déjà
   filtrés à l'étape 1 — leur `confidence` est donc **toujours ≥ 0.85** par
   construction. La condition `result.confidence < AudioConstants.minConfidence`
   à la ligne 78 est donc **toujours fausse : code mort**, jamais atteint en
   pratique.

**Piste de correction** : décider quel niveau doit porter le filtre de
confiance.
- Option A (probablement la bonne) : ne pas `return` en silence dans l'isolate
  quand la confiance est insuffisante mais qu'une corde cible est sélectionnée
  — renvoyer quand même le résultat (avec sa faible confiance) pour que le
  BLoC puisse détecter la situation et activer le filtre IIR. Le `return`
  actuel a probablement été pensé uniquement pour éviter d'afficher une note
  peu fiable en mode AUTO, sans anticiper le besoin du scénario A2.
- Option B : déplacer l'auto-activation dans l'isolate lui-même, à côté du
  filtre IIR (`filter?.process(samples)`), puisque c'est là que la confiance
  brute est disponible avant filtrage.

À trancher avant implémentation : impact sur `ITN-03` (désactivation à la
désélection de corde) et sur la stabilité du filtre IIR si on l'active sur un
échantillon isolé à faible confiance plutôt que sur une tendance.

---

## BUG-02 · LIFE-02 — L'écoute ne reprend jamais après un retour au premier plan

**Constat recette** : après mise en arrière-plan puis retour sur l'app, plus
aucune détection de son ; seul un kill + relance de l'app rétablit l'écoute.
**Bloquant** : `LIFE-01/02` fait partie des critères de sortie explicites de
`CAHIER_DE_RECETTES.md` §11.

**Portée plus large que prévu** : ce même bug est aussi la cause de l'échec de
**PERM-02, PERM-03 et PERM-04**. Pour révoquer la permission micro entre deux
scénarios, il faut passer par Réglages Android — ce qui met l'app en pause
exactement comme dans LIFE-02. Au retour :
1. Le passage en pause a fait émettre `TunerInitial` (voir `_onStop` ci-dessous).
2. Comme ce bug empêche `StartTuner` d'être redéclenché après un état
   `TunerInitial`, l'app ne relance jamais `_subscribeToRepo()`.
3. Comme `_subscribeToRepo()` n'est jamais rappelé, la vérification de
   permission (`record_microphone_data_source.dart:24-35`) n'est jamais
   exécutée non plus — l'app ne peut donc **jamais atteindre**
   `TunerPermissionDeniedState`, et reste affichée sur l'écran Tuner standard
   (`_TunerContent`, cf. `tuner_screen.dart:48-60`) mais sans aucune activité
   (aiguille figée, aucune détection), au lieu de l'écran de blocage attendu.

Un seul correctif sur ce bug devrait donc résoudre 4 des 6 anomalies KO de
cette session de recette.

**Cause racine** — `tuner_bloc.dart:166-176` :
```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    if (!isClosed) add(const StopTuner());
  } else if (state == AppLifecycleState.resumed &&
      this.state is TunerListening) {
    if (!isClosed) add(const StartTuner());
  }
}
```
`StopTuner` déclenche `_onStop` (`tuner_bloc.dart:65-70`), qui **émet
`TunerInitial()`** — donc dès que l'app passe en `paused`, `this.state`
n'est plus `TunerListening`. Au retour en `resumed`, la condition
`this.state is TunerListening` à la ligne 173 est par construction **toujours
fausse** (l'état a été changé en `TunerInitial` par la mise en pause
elle-même) : `StartTuner` n'est donc **jamais** redéclenché automatiquement.
Le bug est systématique, pas intermittent.

**Piste de correction** : la reprise doit se baser sur un état conservé
*avant* le passage à `TunerInitial`, pas sur `this.state` au moment du
`resumed`. Par exemple, mémoriser un flag `_wasListeningBeforePause` (mis à
`true` dans le handler `paused` avant `add(StopTuner())`, remis à `false`
après un `StartTuner` réussi) et tester ce flag plutôt que `this.state` à la
ligne 172.

---

## BUG-03 · NAV-02 — Le micro continue d'écouter en dehors de l'onglet Tuner

**Constat recette** : en jouant une note depuis l'onglet Presets, la nouvelle
note est affichée au retour sur l'onglet Tuner → confirme le doute déjà
consigné dans `CAHIER_DE_RECETTES.md` (anomalie Green IT).

**Cause racine** : `main_shell.dart:30` utilise `IndexedStack`, qui garde
tous les écrans (dont `TunerScreen`/`TunerBloc`) montés en permanence pour
éviter les rebuilds au changement d'onglet. Rien ne déclenche `StopTuner`
lors d'un changement d'onglet — seuls `didChangeAppLifecycleState`
(mise en arrière-plan de l'app entière, cf. BUG-02) et les boutons explicites
de l'écran Tuner (`tuner_screen.dart:38,108,254`) envoient `StartTuner`/
`StopTuner`. Le micro reste donc actif tant que l'app est au premier plan,
quel que soit l'onglet affiché.

**Piste de correction** : détecter la visibilité de l'onglet Tuner
indépendamment du cycle de vie de l'app — soit en écoutant l'index courant
du `IndexedStack` depuis `TunerScreen` (ex. `VisibilityDetector` ou callback
remonté depuis `main_shell.dart` sur changement d'onglet) et en déclenchant
`StopTuner`/`StartTuner` en conséquence, soit en acceptant explicitement ce
comportement comme voulu (écoute continue multi-onglets) — à trancher avec le
porteur de projet, car cela impacte aussi le budget batterie/Green IT mis en
avant comme exigence du projet.

---

*harmonixTune — PLAN_CORRECTION_BOGUES v1.0*
