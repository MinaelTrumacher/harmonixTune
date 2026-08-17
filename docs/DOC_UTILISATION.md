# harmonixTune — Documentation d'utilisation

> Guide utilisateur de l'application. Décrit **ce que fait** l'application et
> **comment s'en servir** — pas comment elle est construite (`DOC_REALISATION.md`)
> ni comment la déployer (`DOC_DEPLOIEMENT.md`).

---

## 1. Présentation

harmonixTune est un accordeur pour instruments à cordes (guitare, basse,
ukulélé), conçu pour une détection rapide et fiable même en environnement
bruyant, sans publicité ni distraction. L'application comporte 3 onglets,
accessibles depuis la barre de navigation en bas de l'écran :

| Onglet | Icône | Rôle |
|---|---|---|
| **Tuner** | 🎛️ | Accordeur en temps réel (fonctionnel) |
| **Presets** | 🎵 | Gestion de profils d'accordage personnalisés (fonctionnel) |
| **Chords** | 🎹 | Reconnaissance d'accords (à venir — écran non fonctionnel dans cette version) |

## 2. Premier lancement — permission microphone

Au premier lancement, l'application demande l'accès au microphone : c'est
indispensable pour détecter les notes jouées, l'app n'a pas d'autre usage du
micro (aucun enregistrement, aucune transmission audio, cf.
`EXIGENCES_SECURITE.md`).

- **Si vous acceptez** : l'écran Tuner s'active immédiatement.
- **Si vous refusez** : un écran d'explication s'affiche avec un bouton
  **Réessayer**.
- **Si vous avez refusé définitivement** ("Ne plus demander") : le bouton
  devient **Ouvrir les réglages**, qui vous amène directement aux
  paramètres système de l'app pour réactiver la permission.

## 3. Écran Tuner

### 3.1 Éléments affichés

- **Aiguille** (cadran demi-cercle) : penche à gauche si la note est trop
  basse, à droite si trop haute, se centre quand la note est juste.
- **Barre de cents** : jauge horizontale, la bille indique l'écart en cents
  par rapport à la note cible. `✓ IN TUNE` s'affiche en vert quand l'écart
  est quasi nul.
- **Nom de note + fréquence** : note détectée (ex. "E4") et sa fréquence en
  Hz.
- **Code couleur** : bleu = trop bas, vert = juste, ambre = presque juste,
  rouge = trop haut, gris = pas de signal détecté.

### 3.2 Sélecteur de cordes

En bas de l'écran, une rangée de cordes (ex. E2, A2, D3, G3, B3, E4 pour une
guitare standard) :

- **Mode AUTO** (par défaut, aucune corde en surbrillance) : l'app détecte
  n'importe quelle corde jouée.
- **Mode manuel** : appuyez sur une corde pour la cibler spécifiquement
  (utile en environnement bruyant) ; appuyez à nouveau dessus pour revenir en
  mode AUTO.

### 3.3 Intelli-Tuner

Toggle en haut de l'écran. En mode manuel (corde ciblée), si le signal capté
est peu fiable (bruit ambiant important), l'Intelli-Tuner s'active
**automatiquement** et isole la fréquence de la corde ciblée pour stabiliser
la détection. Activable aussi manuellement à tout moment.

### 3.4 Chips "Standard" / "Guitar"

Visibles en haut de l'écran Tuner — **non fonctionnels dans cette version**
(réservés à une sélection rapide de preset directement depuis l'écran Tuner,
prévue dans une prochaine itération ; la gestion des profils se fait pour
l'instant exclusivement depuis l'onglet Presets, cf. §4).

### 3.5 Comportement en arrière-plan

Le microphone se coupe automatiquement dès que l'application passe en
arrière-plan (autre app au premier plan) ou dès que vous quittez l'onglet
Tuner pour un autre onglet — l'écoute reprend seule au retour, sans action de
votre part.

## 4. Écran Presets

Liste de vos profils d'accordage personnalisés, disponibles hors connexion
(stockage local).

- **Créer un profil** : bouton `+` en bas à droite → renseignez un nom (3 à
  50 caractères), un type d'instrument (guitare/basse/ukulélé/personnalisé —
  change automatiquement le nombre de cordes par défaut), puis les notes de
  chaque corde (format `<note><octave>`, ex. `E2`). Vous pouvez ajouter
  (jusqu'à 8) ou retirer (jusqu'à 3 minimum) des cordes via les boutons dédiés.
- **Enregistrer** : le bouton **Enregistrer le profil** valide les règles
  métier (nom non dupliqué, nombre de cordes, fréquences dans la plage
  détectable ~43-1200 Hz) — un message d'erreur s'affiche sous le champ
  concerné si une règle n'est pas respectée, sans fermer l'écran.
- **Supprimer un profil** : icône corbeille sur la tuile du profil concerné.
- **Écran vide** : si aucun profil n'existe encore, un message d'accueil
  explique comment en créer un.

## 5. Écran Chords

Non fonctionnel dans cette version (affiche un texte de statut). La détection
d'accords polyphonique est en cours de conception technique
(`UC_03_strategy.md`) — disponible dans une prochaine version.

## 6. Résolution de problèmes courants

| Symptôme | Cause probable | Solution |
|---|---|---|
| Écran "Accès au microphone requis" persistant | Permission refusée | Réessayer, ou vérifier les réglages système si le bouton propose "Ouvrir les réglages" |
| Aiguille immobile, aucune détection | Signal trop faible/silence, ou note en dehors de la plage détectable (~43 Hz mini) | Jouer plus fort/plus près du micro ; vérifier que l'instrument n'est pas anormalement grave |
| Détection instable en environnement bruyant | Confiance de détection faible | Sélectionner la corde manuellement (mode manuel) — active l'Intelli-Tuner automatiquement si besoin |
| Rien ne se passe en changeant d'onglet puis en revenant sur Tuner | Comportement normal | Le micro se réactive automatiquement, un court délai est normal |

## 7. Plateformes et prérequis

| Plateforme | Statut |
|---|---|
| Android | Supporté (version testée : builds `dev`/`staging`/`prod`, cf. `DOC_DEPLOIEMENT.md`) |
| iOS | Supporté au niveau code (permission micro déclarée) — build/validation complète nécessite un poste macOS, non encore testé sur device réel dans le cadre de ce projet |

---

*harmonixTune — DOC_UTILISATION v1.0*
