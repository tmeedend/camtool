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
`luajit tests/run.lua` (158 tests au dernier point). Le binaire n'est pas dans
le `PATH` des sessions d'outillage : voir `CLAUDE.md`.

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

### Ce qui se teste maintenant hors jeu

La chaîne de lecture est sortie de `CamTool3.lua` : elle vit dans
`core/playback.lua`, pure, sans `ac` ni CSP, entrées et sorties en nombres
simples. L'app n'en garde que ce qui parle au jeu. `CamTool3.lua` passe de 1103
à 875 lignes.

Ce que ça ouvre, et qui demandait un lancement d'AC jusqu'ici :

- **Un tour entier hors jeu** (`tests/lap.lua`), au choix à travers l'app et les
  faux CSP, ou directement dans le core. La voiture suit le tracé **réellement
  enregistré** dans le fichier caméra quand il y en a un — deux fichiers de
  référence en portent un, donc les distances et les angles sont ceux du jeu.
- **Golden master** (`tests/fixtures/playback_golden.lua`) : quatre scénarios
  figés frame par frame. Sensibilité vérifiée : 1e-6 rad sur la visée fait
  tomber les quatre. À regénérer **seulement** pour un changement de
  comportement voulu, et à dire dans le commit.
- **Rejeu de traces CamTool 2** (`tests/trace.lua`) : l'oracle. CamTool 2
  enregistre en jeu ce qu'on lui donne et ce qu'il demande à la caméra ; le
  rejeu redonne ces entrées à `core/playback` et mesure l'écart, paramètre par
  paramètre. **Il manque l'enregistrement** — voir « En attente de Théo ».
- **Balayage d'invariants** (`tests/sweep.lua`) : `inf`/`nan`, vecteur look non
  unitaire, FOV hors bornes, distance de focus négative, caméra qui se
  téléporte au milieu de son plan, caméra inatteignable. Les seuils sont des
  ratios (un plan est fluide à n'importe quelle vitesse), stables de 600 à
  10800 frames par tour. Chaque règle a son test de morsure : une règle qui ne
  se déclenche jamais ne vaut rien.

Rien de neuf trouvé dans les quatre fichiers de référence. **#23 est maintenant
mesuré et plus seulement décrit** : la dernière caméra de `le_lancone` tient 54°
de FOV là où elle devrait zoomer à 12°, et le correctif ne change que ça.

Ce que ça ne couvre toujours pas : l'image (flou, artefacts, UI).

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

### 2. Enregistrer une trace (15 minutes en jeu, une fois)

L'enregistreur **est écrit et commité**, des deux côtés. Ce qui manque est
l'enregistrement lui-même, que seul un lancement d'AC peut produire.

Ce que ça donne : l'**oracle**. Le golden master dit « ça n'a pas changé », le
balayage dit « ce n'est pas cassé » ; seul CamTool 2 peut dire « c'est ce que
CamTool 2 fait ». Une session achète la réponse pour de bon, rejouable sans
toi.

Marche à suivre :

1. Ajouter `"dev_record_trace": true` dans `apps/python/CamTool_2/settings.json`
   (le défaut dans `Settings.__init__` ne suffit pas : `load_settings` remplace
   tout le dictionnaire — le piège était bien réel, il est documenté et
   contourné).
2. Lancer AC, ouvrir CamTool 2, charger le fichier caméra du scénario, jouer le
   replay. L'enregistrement s'arrête seul au bout de **deux minutes**. Console
   AC : `recording a trace to ...`.
3. Le fichier arrive dans `apps/python/CamTool_2/traces/` (ignoré par git).
4. Conversion, depuis `apps/lua/CamTool3/` :
   `python tools/trace_to_lua.py <la trace>.jsonl tests/fixtures/trace_<nom>.lua`
5. Ajouter la trace à `RECORDINGS` dans `tests/test_trace_replay.lua`, lancer,
   et inscrire les écarts mesurés comme tolérances.

Scénarios proposés : Silverstone `seb` (splines), `le_lancone` (dernière
caméra, là où #23 se voit).

**À savoir avant de lire les écarts.** Le rejeu ignore volontairement les
frames enregistrées pendant un mouse look (CamTool 2 y mélange sa sortie avec
la position courante de la caméra, ce que le portage ne modélise pas), et le
smart tracking n'est pas porté : les caméras qui l'utilisent divergeront par
construction. La valeur est dans la **localisation** de l'écart.

Ce que ça n'apporte pas : rien sur l'image, et la comparaison se fait contre
CamTool 2 **bugs compris** — voulu pour le mode `legacy`, muet sur la qualité
d'une correction.

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
   l'appelle avec. Le balayage le constate : sur Red Bull Ring, 9 caméras sur 11
   se déclenchent, les deux manquantes sont les caméras de stand.
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
