# Où on en est

> **À lire en premier en reprenant le projet.** Ce fichier bouge à chaque
> avancée. Les règles et contraintes sont dans `CLAUDE.md`, le savoir accumulé
> sur CamTool 2 dans `docs/legacy.md`.

## État des branches

| Branche | Rôle |
|---|---|
| `main` | CamTool 2 en production. Les correctifs 2.x se font ici. |
| `camtool-3` | **Branche de travail.** CamTool 3 en Lua, dans `apps/lua/CamTool3/`. |
| `poc/lua` | Le POC qui a fondé la décision Lua. Conservée comme repère, figée. |
| `develop`, `feature/*` | Antérieures au projet CamTool 3. |

**Rien n'est poussé sur `origin`** à ce jour : tout le travail CamTool 3 est
local.

Validation avant toute modification, depuis `apps/lua/CamTool3/` :
`luajit tests/run.lua` (107 tests au dernier point).

## ✅ Décision actée : CamTool 3 sera une app Lua CSP

Tranché par Théo après le POC (branche `poc/lua`, conservée comme repère). Le développement continue sur `camtool-3`, dans `apps/lua/CamTool3/`.
**CamTool 2 reste en Python et continue d'être maintenu sur `main`** ; les
sections Python de ce document restent valables pour les correctifs 2.x.

Ce que le POC a prouvé **en jeu**, et qui fonde la décision :

- Les **6 appels DLL** ont un remplaçant Lua fonctionnel (voir le tableau plus
  haut). L'objectif « zéro DLL » est atteint.
- La brique centrale : placer la vue → capturer → rejouer la pose à l'identique.
- Le **rejeu d'une vraie caméra utilisateur** de bout en bout : fichier lu,
  migré, caméra sélectionnée par la position piste, paramètres interpolés,
  caméra pilotée, voiture suivie.
- Les **32 fichiers existants** se chargent : 566 caméras, 1768 valeurs de FOV,
  aucune perte.

Et hors jeu : une boucle de test réelle (LuaJIT + runner maison), avec les trois
interpolateurs confrontés point par point au vrai code Python.

### Déjà porté et validé en jeu

Migration des fichiers, sélection de la caméra par position piste, les trois
interpolateurs, conventions d'angles, tracking avec anticipation (lead/lag),
splines enregistrées, shake (rotation et offset), profondeur de champ avec
autofocus, fonctionnement fenêtre fermée.

**Issues traitées** : **#16** (glissement à l'activation) et **#23** (dernière
caméra figée) ont leur cause identifiée, confirmée en jeu, et un correctif
disponible derrière une case à cocher. **#20** (stuttering) ne se reproduit pas
en Lua. **#25** et **#37** ont des éléments concrets dans `docs/legacy.md`.
**#38** n'a pas pu être reproduit.

## ⏳ En attente de Théo

Ce que la session précédente a laissé en suspens. **À lire avant de proposer la
suite.**

### 1. Test en jeu non fait : shake et profondeur de champ

Le portage est commité et testé hors jeu, mais **personne ne l'a vu tourner**.

- Charger un fichier, `Grab camera` (le mode lecture se sélectionne seul).
- **Shake** : décocher/recocher `apply shake`. Puis **rejouer deux fois le même
  passage** — le tremblement doit être *identique*, c'est le test qui compte
  (l'horloge dérive de la position de replay, pas du temps réel).
- **Profondeur de champ** : une caméra avec `Autofocus`, vérifier que la
  distance affichée suit la voiture. Décocher `apply depth of field` pour
  comparer.
- Réserve : le DOF exige **YEBIS** actif dans CSP. Distance qui bouge mais rien à
  l'écran = probablement ça, pas un bug du portage.

### 2. Décision non prise : enregistreur de traces

Proposé, pas encore tranché. L'idée vient de la section Tests de `CLAUDE.md`.

**Principe** : CamTool 2 enregistre par frame ses entrées (dt, position piste,
frame de replay, positions des voitures) et ses sorties (position caméra, cap,
tangage, roulis, FOV, focus) dans un JSONL. Je rejoue ces entrées dans le core
Lua hors jeu et je compare les sorties.

**Ce que ça apporte** : un golden master de la **chaîne entière**, là où les
tests actuels vérifient les fonctions isolément. C'est précisément là que les
bugs se sont logés (repli du cap non keyframé, DOF écrasé par la sonde). Une
seule session d'enregistrement achète une couverture de non-régression
permanente, rejouable sans Théo.

**Ce que ça n'apporte pas** : rien sur l'image (flou, artefacts, UI), et la
comparaison se fait contre CamTool 2 **bugs compris** — ce qui est voulu pour le
mode `legacy`, et muet sur la qualité d'une correction.

**Coût** : ~100 lignes Python côté CamTool 2 (désactivé par défaut, hors chemin
chaud, aucune modification du calcul) + ~100 lignes Lua de chargeur et
comparateur + 2-3 traces courtes en fixtures.

⚠️ **Piège repéré** : `Settings.load_settings()` *remplace* tout le dictionnaire
par le contenu du fichier. Un nouveau défaut ne prendrait donc pas effet sur un
`settings.json` existant — lire le drapeau avec un repli explicite.

Scénarios proposés : Silverstone `seb` (splines), `le_lancone` (dernière caméra).

## Chantiers restants, par taille croissante

1. **Compléter `docs/ui-inventory.md`** — l'essentiel est fait, recoupé avec
   cinq captures fournies par Théo : libellés réels, unités, code couleur,
   disposition, les cinq onglets, le formulaire de fichiers. Huit points restent
   ouverts en fin de document, **tous relevant désormais de la lecture de code**.
   Deux méritent d'être traités avant la refonte : la portée du bouton `Reset`
   (potentiellement destructif) et le déroulé de `Record`.
2. **Caméras de stand** : le portage les *saute* correctement sur piste, mais ne
   sait pas encore les *sélectionner* quand la voiture est aux stands (le legacy
   le fait via `car_is_in_pitline`, avec une seconde passe de sélection).
   `evaluate.activeCameraIndex` accepte déjà un argument `wantPit`, rien ne
   l'appelle avec.
3. **Smart tracking** (`calculate_cam_rot_to_smart_tracking_car`).
4. **L'UI** (maquette ATR) — le gros du travail, sans risque technique connu.
5. **L'écriture de fichiers** — jusqu'ici volontairement hors périmètre. Voir la
   migration à sens unique dans `docs/legacy.md` : on écrit toujours le format v1.

### Réserves connues, non bloquantes

- **Mouse look** : la visée est moins douce que dans CamTool 2. La cause est
  identifiée : le legacy pilote la caméra avec la **moyenne des 60 dernières
  positions de souris**, et le bouton gauche commande le remplissage de ce
  tampon — le relâcher laisse la caméra finir sur son élan. Le portage envoie le
  delta brut. Reproduire la moyenne glissante, pas un lissage exponentiel (voir
  `docs/ui-inventory.md`).
- **`transform_loc_strength`** n'est pas appliqué (il vaut 1.0 sur les 566
  caméras de référence et n'est jamais keyframé, donc sans effet aujourd'hui).

## Décisions ouvertes (ne pas trancher seul)

- Déplacement éventuel du dépôt hors du dossier du jeu (jonction Windows vers `apps/python/CamTool_2`).
- `interpolation_mode` est **par fichier** ; le passer par caméra permettrait de
  mélanger anciennes et nouvelles caméras dans un même set.
- Le **bug `SolveCubic`** (registre des bizarreries) : corriger dans le mode
  `fixed`, ou le garder tel quel ?
- **#23 : le correctif par défaut ?** Il est aujourd'hui derrière une case à
  cocher, legacy par défaut, donc les fichiers migrés gardent le bug. À la
  différence des bugs de courbe (#1, #4) qui *déplacent* une trajectoire, #23
  remplace l'animation voulue par **rien** — la caméra ignore ses keyframes.
  Difficile d'imaginer une vidéo qui en dépende.
