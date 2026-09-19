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
`luajit tests/run.lua` (250 tests au dernier point). Le binaire n'est pas dans
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

## 🎮 Jamais vu en jeu — à tester

Tout ce qui suit est écrit, testé hors jeu et commité, mais **personne ne l'a
vu tourner**. À reprendre dans l'ordre ; ce qui casse en premier casse
probablement le reste.

**Avant tout : copier `apps/python/CamTool_2/data/` ailleurs.** Les garde-fous
sont testés, mais c'est la première fois que ce code écrit, et ça ne coûte
rien.

| # | Quoi | Comment savoir que c'est bon |
|---|---|---|
| 1 | Shake et profondeur de champ | Rejouer deux fois le même passage : le tremblement doit être **identique**. DOF : une caméra en `Autofocus`, la distance suit la voiture. Réserve : le DOF exige **YEBIS** actif dans CSP. |
| 2 | Courbes de FOV | Un zoom doit maintenant suivre la même courbe que CamTool 2 — c'est le correctif de l'espace d'interpolation. Comparer à l'œil sur le même passage. |
| 3 | Autofocus respecté | Une caméra avec `AF` éteint ne doit plus faire le point sur la voiture (24 caméras sur 589 sont dans ce cas). |
| 4 | Panneau ATR, lecture | Bande des caméras, bande des keyframes, losanges à trois états, unités, colonnes alignées. |
| 5 | Panneau ATR, édition | Flèches, glisser (8 px par pas), double-clic pour taper. **Le plus important : taper `35` dans `FOV` doit donner `35.00 deg`**, et pareil sur `PITCH` (degrés → radians) et `STR PITCH` (pourcent → 0..1). |
| 6 | Ctrl / Shift | Quatre fois plus fin, quatre fois plus gros. Sauf sur `FOV` et `Focus point`, où c'est normal qu'ils ne fassent rien. |
| 7 | Annuler / refaire | Boutons et Ctrl+Z / Ctrl+Y, y compris sur les ajouts de caméras et de keyframes. |
| 8 | `+` / `−` | Un keyframe naît **à la tête de lecture** et se sélectionne seul. `−` refuse le dernier keyframe d'une caméra et la dernière caméra d'un fichier. |
| 9 | `Reset` | Le **premier** clic prévient seulement. |
| 10 | Section SPLINE | Apparaît avec le nombre de points sur Silverstone `seb`, disparaît sur une caméra sans tracé. |
| 11 | **Sauvegarde** | Écrit dans `apps/lua/CamTool3/data/`, **jamais** dans celui de CamTool 2. Vérifier que le fichier d'origine n'a pas changé de date. Recharger doit retrouver les modifications. |
| 12 | **Caméras AC** | Sur `le_lancone`, la caméra 5 demande la vue **volant**. CamTool 3 doit passer la main : la vue devient celle d'AC, et revient quand la caméra suivante reprend. Onze caméras de référence sont dans ce cas. |
| 13 | Session autonome | Ouvrir **seulement** la fenêtre ATR et travailler sans jamais ouvrir le panneau de sondes. |

## ⏳ En attente de Théo

Ce qui demande le jeu et n'est pas dans la checklist ci-dessus.

### Une trace qui contienne la dernière caméra (#23)

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
soucier du retour en arrière. ✅ **Fait** (`core/serialise.lua`,
`storage.saveCameraFile`).

⚠️ **La sauvegarde écrase des fichiers irrécupérables** (`data/` est
gitignoré). Trois garde-fous : le texte est construit et vérifié avant
d'ouvrir quoi que ce soit (un `inf` ou un `nan` **annule** la sauvegarde),
`io.save` écrit dans un temporaire puis déplace, et le premier écrasement
d'un fichier en garde une copie `.camtool3-backup`. `tools/check_serialise.py`
rejoue un vrai fichier Lua → JSON → Python et compare champ par champ.

**Ordre convenu pour la suite** (proposé par le designer UX, validé) :

1. ✅ **Fait.** Le composant paramètre unique, le point d'entrée unique
   (`core/edit.lua`) et les quatre gestes : losange (keyframe), flèches (pas),
   glisser (scrub, 8 px par pas), double-clic (saisie). Chaque modification
   rend un enregistrement réversible — l'annuler/refaire est déjà une pile,
   avec un bouton. Les unités savent aller dans les deux sens : taper 45 dans
   un champ en degrés arrive bien en radians.
2. **L'ISO — fait, sauf trois choses qui ne sont pas de l'UI.** Ajout et
   suppression de caméras et de keyframes, position du keyframe, `Pit only`,
   `Specific cam`, bascule position/temps, les 11 paramètres de l'onglet
   Spline, `Save`, `Load`, `Reset` (avec confirmation).

   « Onglet Settings » cachait trois natures de travail différentes. Ce qui
   reste vraiment : **enregistrer une spline** (fonctionnalité par frame, pas
   un panneau — c'est le portage de `record_spline`), **`load on startup` et
   les raccourcis** (demandent un fichier de réglages que CamTool 3 n'a pas),
   et **`Activate Free Camera`**.

   ⚠️ **Écart assumé avec CamTool 2** : `+` crée un keyframe **à la tête de
   lecture**. Le legacy le crée sans position (`keyframe = None`) et oblige à
   le placer ensuite avec la barre rouge — d'où le rôle de cette barre, qui
   n'est pas de la navigation mais **le seul moyen de placer un keyframe**
   (`CamTool_2.py:1738`). Le fichier produit est le même, l'étape en moins.
3. ✅ **Annuler / refaire faits**, boutons et Ctrl+Z / Ctrl+Y, y compris sur
   les ajouts et suppressions de caméras et de keyframes.
4. La **bande de piste** (un ruban 0 → longueur du circuit, chaque caméra sur
   son segment, keyframes en losanges, tête de lecture), qui remplacerait à
   elle seule la grille, `Starting point` et la barre de keyframe — et passe
   à l'échelle de l'issue **#6** (plus de 99 caméras). Puis la **mini-carte**
   tracée depuis `track_spline`, déjà dans les fichiers.

Idée notée, non tranchée : **nommer les caméras** (« Sortie Eau Rouge » plutôt
que « 6 »), un champ texte de plus dans le JSON, le numéro restant pour la
compatibilité.

## 📁 Fichiers : deux dossiers, deux formats

**CamTool 3 n'écrit jamais dans le dossier de CamTool 2.**

| Dossier | Rôle |
|---|---|
| `apps/python/CamTool_2/data/` | Les fichiers de l'utilisateur. **Lecture seule.** Hors git, certains ont des années. |
| `apps/lua/CamTool3/data/` | Ce que CamTool 3 écrit. Créé à la première sauvegarde, ignoré par git. |

Ouvrir un fichier CamTool 2 et le sauvegarder en fait une **copie** dans le
dossier CamTool 3 ; l'original reste tel que CamTool 2 l'a laissé. C'est la
migration à sens unique de `docs/legacy.md`, rendue visible dans le système de
fichiers. Le panneau liste les deux, les siens d'abord, ceux de CamTool 2
marqués — une fois qu'un fichier a été sauvé ici, c'est cette copie qu'on
travaille.

Raison concrète : CamTool 2 liste `*.json` de son dossier et **échouerait** à
charger un document v1. Son chargeur parcourt les clés de premier niveau comme
si c'étaient des listes de caméras, trébucherait sur `version` et
`interpolation_mode`, avalerait l'exception et n'afficherait rien.

### Reconnaître un fichier CamTool 2 d'un fichier CamTool 3

`data.versionOf(raw)` : **absence de champ `version` = CamTool 2** (version 0).
CamTool 2 n'a jamais écrit ce champ, CamTool 3 l'écrit toujours. La détection
est donc fiable, et c'est elle qui déclenche la migration.

### Les deux axes, à ne pas confondre

- **`version`** — comment les valeurs sont **encodées** sur le disque. v0 : FOV
  en `1/(fov+15)`. v1 : FOV en degrés. Migration testée, à sens unique.
- **`interpolation_mode`** — quelles **maths de courbe** s'appliquent.
  `legacy` reproduit CamTool 2, bizarreries comprises ; `fixed` applique les
  corrections.

Les collapser serait tentant et faux : migrer l'encodage ne doit pas changer
les courbes d'un montage déjà fait. Un fichier CamTool 2 migré est donc
**v1 + legacy**.

**Les deux cases « legacy » du panneau de sondes ne sont plus des préférences.**
`playback.applyMode` les dérive de `interpolation_mode` au chargement, et le
panneau ATR affiche le mode et permet d'en changer volontairement. Réponse à
la question « faut-il les cocher pour un fichier CamTool 2 ? » : **non, le
fichier le dit**. Les cases restent dans le panneau de sondes comme outil de
diagnostic.

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
4. ~~**`camera_use_specific_cam`**~~ — **fait** (`core/cameramode.lua`).
   Le champ s'appelle `AC CAMERA` dans le panneau et affiche les noms de
   CamTool 2 (« volant », « derrière », « cockpit »…) plutôt qu'un numéro.

   **Ce que CSP a apporté** : `ac.setCurrentDrivableCamera` et
   `ac.setCurrentCarCamera` prennent la caméra voulue. CamTool 2 ne pouvait
   pas — pour la famille F1 il **appuyait sur F1 le bon nombre de fois**
   depuis un décalage mémorisé (`CamMode.changeCamModeZero`), d'où la
   synchronisation manuelle que l'utilisateur devait faire avant. Elle
   disparaît.

   Passer la main = demander la caméra **et** cesser d'écrire le transform :
   `ownShare` à 0 laisse passer la vue d'AC à travers le grab qu'on garde,
   donc reprendre la main est juste le remettre. Le changement se fait au
   changement, pas à chaque frame, pour ne pas se battre avec quelqu'un qui
   appuie sur F1.
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
