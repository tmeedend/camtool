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

Validation avant toute modification, depuis `apps/lua/CamTool3/` :
`luajit tests/run.lua` (203 tests au dernier point). Le binaire n'est pas dans
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
  paramètre. **Deux traces réelles sont commitées** (Silverstone `seb`,
  le_lancone `lancia`) — voir les résultats plus bas.
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

### 2. Une trace qui contienne la dernière caméra (#23)

Deux traces sont faites — Silverstone `seb` et le_lancone `lancia`, 7200
frames chacune. **Ce qu'elles ont donné est plus bas.**

Il manque le scénario #23 : le_lancone fait 7,3 km, et deux minutes de replay
ne couvrent que le **premier tiers** du tour. L'enregistrement s'arrête donc
bien avant la ligne, et la dernière caméra — celle qui porte #23 — n'y est
jamais active. Pour l'attraper : **positionner le replay juste avant la ligne
d'arrivée** avant d'activer l'app.

Marche à suivre, depuis `apps/lua/CamTool3/` :

1. `"dev_record_trace": true` dans `apps/python/CamTool_2/settings.json`
   (`load_settings` remplace tout le dictionnaire, donc le défaut de
   `Settings.__init__` ne suffit pas — piège réel, documenté et contourné).
2. Jouer le replay, app **activée**. Arrêt automatique à deux minutes.
3. `python tools/trace_to_lua.py <trace>.jsonl tests/fixtures/trace_<nom>.lua N`
4. Ajouter l'entrée à `RECORDINGS` dans `tests/test_trace_replay.lua`.

## 🎯 Ce que les traces ont dit

Deux sessions, 7200 frames chacune, comparaison de ce que chaque côté demande à
la caméra. État après corrections :

| mesure | Silverstone `seb` | le_lancone `lancia` |
|---|---|---|
| position | 2,3 × 10⁻¹³ m | **0** |
| sélection de caméra | 0 / 7200 | 0 / 7200 |
| FOV | 7,1 × 10⁻¹⁵ ° | 7,1 × 10⁻¹⁵ ° |
| focus | 6,4 × 10⁻⁶ m | 464 m (frame 0) |
| tangage | 0,014 rad | 8,6 × 10⁻¹² rad |
| roulis | 9,9 × 10⁻⁷ rad | 0 |
| cap | 0,130 rad | 0,354 rad (3 frames) |

**#16 confirmé en session réelle** : avec `legacyZeroFill` désactivé, le cap
part à 1,56 rad sur les premières frames puis colle ; activé, l'écart tombe à
0,13. Le diagnostic tenait.

**Trois défauts trouvés et corrigés**, tous invisibles sans oracle :

- **FOV interpolé dans le mauvais espace.** CamTool 2 interpole la forme
  stockée `1/(fov+15)` et convertit après ; le portage convertissait à la
  migration. Jusqu'à **3,6° d'écart sur un 25°**, égal aux keyframes et
  divergent entre les deux. Corrigé dans `core/evaluate`.
- **Autofocus actif partout.** `camera_use_tracking_point` vaut 0 ou 1 et
  **0 est vrai en Lua** — 24 caméras sur 589 concernées. Corrigé via
  `data.isOn`.
- **Porte de refocalisation et distance tenue.** CamTool 2 interroge la porte
  avec le cap de la frame **précédente** (`ctt` met le cap en cache, que
  `set_rotation` ne vide pas) et avec la visée *brute*, normalisée sur la
  branche du cap. Et quand il tient, il tient ce que la caméra a réellement,
  pas la dernière valeur qu'il a calculée. Le focus passe de 500 m à 6 × 10⁻⁶.

**Ce qui reste n'est pas du portage, c'est l'état d'avant la trace :**

- La **phase du shake** (0,13 rad sur Silverstone). L'horloge de repli de
  CamTool 2 cumule `dt` depuis le démarrage de l'app ; une trace qui commence
  en cours de session ne peut pas la reconstituer. Les caméras sans shake sont
  à zéro exactement.
- Le **cap et le focus d'avant la première frame** (3 et 5 frames sur 7200
  pour le_lancone, toutes à un changement de caméra). Le focus est désormais
  enregistré (`focus0`, lecture CSP non cachée donc sans risque) ; le cap ne
  peut pas l'être, le lire en jeu remplirait un cache que le jeu remplit plus
  tard.

## 🎨 La refonte UI, en cours

`ATR UI` est une **deuxième fenêtre** (`windowAtr`), à côté du panneau de
diagnostic qu'elle ne remplace pas : les sondes servent encore. Elle suffit
désormais à travailler seule — choix du fichier, chargement, prise de la
caméra.

Ce qui est en place : les trois colonnes alignées en `ui.columns`, la bande
des caméras et celle des keyframes (avec `+` / `−` inertes), le losange de
keyframe à trois états, les unités, les champs inactifs grisés, et un
pense-bête en bas qui liste ce qui manque encore.

**Décisions actées avec Théo** (ne pas re-trancher seul) :

- **Une seule UI**, ATR. L'ancienne à onglets n'est pas reproduite.
- **Le losange porte le keyframe** (vide / creux / plein), ce qui libère la
  valeur. Convention des logiciels d'animation, et ça lève l'ambiguïté du
  rouge de CamTool 2.
- **La valeur se glisse** pour scrubber et **se tape** au clavier.
- Couleur saturée en accent d'en-tête seulement ; pastilles en teinte légère.

**Compatibilité de sauvegarde — tranché par Théo** : une sauvegarde CamTool 3
n'a **pas** à être relisible par CamTool 2. On écrit le format v1 sans se
soucier du retour en arrière.

**Ordre convenu pour la suite** (proposé par le designer UX, validé) :

1. ✅ **Fait.** Le composant paramètre unique, le point d'entrée unique
   (`core/edit.lua`) et les quatre gestes : losange (keyframe), flèches (pas),
   glisser (scrub, 8 px par pas), double-clic (saisie). Chaque modification
   rend un enregistrement réversible — l'annuler/refaire est déjà une pile,
   avec un bouton. Les unités savent aller dans les deux sens : taper 45 dans
   un champ en degrés arrive bien en radians.
2. L'ISO : ce qui manque encore, les keyframes, la sauvegarde et le
   chargement.
3. L'annuler / refaire, presque gratuit si 1 est fait.
4. La **bande de piste** (un ruban 0 → longueur du circuit, chaque caméra sur
   son segment, keyframes en losanges, tête de lecture), qui remplacerait à
   elle seule la grille, `Starting point` et la barre de keyframe — et passe
   à l'échelle de l'issue **#6** (plus de 99 caméras). Puis la **mini-carte**
   tracée depuis `track_spline`, déjà dans les fichiers.

Idée notée, non tranchée : **nommer les caméras** (« Sortie Eau Rouge » plutôt
que « 6 »), un champ texte de plus dans le JSON, le numéro restant pour la
compatibilité.

## Chantiers restants, par taille croissante

1. ~~**Compléter `docs/ui-inventory.md`**~~ — **fait.** Il ne reste qu'un point,
   la cadence d'échantillonnage des splines, et il demande le jeu : quinze
   secondes de replay au ralenti avec `dev_record_trace`, le champ `rtm` de la
   trace donne la réponse. Tout le reste est tranché, y compris le pas de
   chaque paramètre, les deux diviseurs de réglage fin (`/5` et `/10`, sans
   doute un accident), et le fait que `Focus point` et `FOV` échappent à la
   règle générale.
2. **Caméras de stand** : le portage les *saute* correctement sur piste, mais ne
   sait pas encore les *sélectionner* quand la voiture est aux stands (le legacy
   le fait via `car_is_in_pitline`, avec une seconde passe de sélection).
   `evaluate.activeCameraIndex` accepte déjà un argument `wantPit`, rien ne
   l'appelle avec. Le balayage le constate : sur Red Bull Ring, 9 caméras sur 11
   se déclenchent, les deux manquantes sont les caméras de stand.
3. **Smart tracking** (`calculate_cam_rot_to_smart_tracking_car`).
4. **`camera_use_specific_cam`** : 11 caméras de référence valent 0, 5 ou 8 —
   CamTool 2 y passe la main à une caméra AC (volant, embarquée…) au lieu
   d'interpoler. Le portage ne connaît pas ce cas et pilotera sa propre caméra.
   Repéré en auditant les types des drapeaux, pas encore traité.
5. **L'UI** (maquette ATR) — le gros du travail, sans risque technique connu.
6. **L'écriture de fichiers** — jusqu'ici volontairement hors périmètre. Voir la
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
