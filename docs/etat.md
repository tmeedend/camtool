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
`luajit tests/run.lua` (531 tests au dernier point). Le binaire n'est pas dans
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

**Les caméras d'Assetto Corsa, y compris la sixième de la famille F1** :
`steering wheel` et `cockpit` donnent bien deux vues différentes, alors que
l'énumération du SDK s'arrête à la cinquième. Détail dans `docs/legacy.md`.

**La carte du circuit et les gestes du panneau** (validés par Théo sur Spa) :
le tracé teinté caméra par caméra, la rotation qui remplit la bande, la
hauteur bornée par la fenêtre, l'anneau de survol, le clic qui sélectionne la
caméra, le bouton `map`, et le glissé de valeur avec sa zone morte, son
curseur ↔ et son Échap.

**Deux bugs que seul le jeu pouvait montrer**, tous deux maintenant épinglés
par un test qui retombe si on les réintroduit :

- **Le clic sur la carte tombait à côté.** Il était mesuré avec `ui.mousePos()`
  (coordonnées écran, soumises à l'échelle de l'UI) alors que le tracé est
  dessiné depuis `ui.getCursor()`. Deux règles différentes. Corrigé en mesurant
  contre l'origine du dessin — et rendu **visible** : l'anneau de survol est le
  même calcul que le clic, donc un désaccord se voit avant de cliquer.
- **Le glissé n'avançait que d'un pas.** Piège ImGui, désormais règle dure dans
  `CLAUDE.md` : `##` hache tout le libellé, seul `###` isole l'identité. La
  partie visible du bouton de valeur *étant* la valeur, elle changeait
  l'identité au premier pas et ImGui lâchait l'élément actif.

**Issues traitées** : **#16** (glissement à l'activation) et **#23** (dernière
caméra figée) ont leur cause identifiée, confirmée en jeu, et un correctif
disponible derrière une case à cocher. **#20** (stuttering) ne se reproduit pas
en Lua. **#25** et **#37** ont des éléments concrets dans `docs/legacy.md`.
**#38** n'a pas pu être reproduit.

## 🎮 Pas encore confirmé en jeu — à tester

Le panneau tourne et Théo y travaille : ce qui suit n'est plus « jamais vu »,
c'est **jamais vérifié**. Écrit, testé hors jeu, commité, mais personne n'a
regardé si le résultat est le bon. À reprendre dans l'ordre ; ce qui casse en
premier casse probablement le reste.

**Avant tout : copier `apps/python/CamTool_2/data/` ailleurs.** Les garde-fous
sont testés, mais c'est la première fois que ce code écrit, et ça ne coûte
rien.

| # | Quoi | Comment savoir que c'est bon |
|---|---|---|
| 1 | Shake et profondeur de champ | Rejouer deux fois le même passage : le tremblement doit être **identique**. DOF : une caméra en `Autofocus`, la distance suit la voiture. Réserve : le DOF exige **YEBIS** actif dans CSP. |
| 2 | Courbes de FOV | Un zoom doit maintenant suivre la même courbe que CamTool 2 — c'est le correctif de l'espace d'interpolation. Comparer à l'œil sur le même passage. |
| 3 | Autofocus respecté | Une caméra avec `AF` éteint ne doit plus faire le point sur la voiture (24 caméras sur 589 sont dans ce cas). |
| 4 | Panneau ATR, lecture | Losanges à trois états, unités, colonnes alignées. Les deux bandes sont vues et fonctionnent. |
| 5 | Panneau ATR, unités | Le glissé et les flèches sont confirmés ; les unités ne le sont pas. **Taper `35` dans `FOV` doit donner `35.00 deg`**, et pareil sur `PITCH` (degrés → radians) et `STR PITCH` (pourcent → 0..1). |
| 6 | Ctrl / Shift | Quatre fois plus fin, quatre fois plus gros. Sauf sur `FOV` et `Focus point`, où c'est normal qu'ils ne fassent rien. |
| 7 | Annuler / refaire | Boutons et Ctrl+Z / Ctrl+Y, y compris sur les ajouts de caméras et de keyframes. |
| 8 | `+` / `−` | Un keyframe naît **à la tête de lecture** et se sélectionne seul. `−` refuse le dernier keyframe d'une caméra et la dernière caméra d'un fichier. |
| 9 | `Reset` | Le **premier** clic prévient seulement. |
| 10 | Section SPLINE | Apparaît avec le nombre de points sur Silverstone `seb`, disparaît sur une caméra sans tracé. |
| 11 | **Sauvegarde** | Écrit dans `apps/lua/CamTool3/data/`, **jamais** dans celui de CamTool 2. Vérifier que le fichier d'origine n'a pas changé de date. Recharger doit retrouver les modifications. |
| 12 | **Caméras AC** | Sur `le_lancone`, la caméra 5 demande la vue **volant**. CamTool 3 doit passer la main : la vue devient celle d'AC, et revient quand la caméra suivante reprend. Onze caméras de référence sont dans ce cas. |
| 13 | Session autonome | Ouvrir **seulement** la fenêtre ATR et travailler sans jamais ouvrir le panneau de sondes. |
| 14 | **Barre d'actions** | Rétrécir la fenêtre : les boutons doivent **passer à la ligne**, jamais sortir par la droite. Tous restent cliquables. |
| 15 | **Bande de piste** | Le ruban sous les bandes numérotées : une teinte par caméra, les losanges de la caméra éditée, le trait blanc de la voiture. Cliquer une portion sélectionne sa caméra, cliquer un losange sélectionne le keyframe. |
| 16 | **Poignée de `camera_in`** | La caméra sélectionnée porte une poignée (point sur la carte, trait sur le ruban). La glisser déplace son début. Elle doit **buter** sur les caméras voisines. Un `Undo` annule **tout le glissé**, pas une frame. |
| 17 | `STARTING POINT` | Ses flèches, son glissé et sa saisie marchent **enfin** — ils ne faisaient rien jusqu'ici. Un pas ≈ 5 m. |
| 18 | **Interrupteur `[strips]`** | Masquer les bandes numérotées et **travailler une vraie session** avec le seul ruban. La question à te poser : est-ce qu'elles manquent ? |
| 19 | **Ruban, édition** | **Clic droit** sur un segment : ajouter une caméra ici, supprimer celle-ci. Glisser la poignée = **une** entrée d'`Undo`. Un losange ne doit **pas** bouger. |
| 20 | **Nom suggéré** | Double-clic sur une caméra sans nom, sur une portion nommée du circuit : le champ s'ouvre **prérempli** (« Les Combes »). Sur une portion sans nom : champ vide. Taper efface la suggestion. |
| 21 | **Clic = amener la voiture** | Cliquer le ruban doit déplacer le replay à cet endroit précis, **sur le tour le plus proche** et pas au premier. **Maj+clic** ne doit rien déplacer. Le son ne doit pas claquer. |
| 22 | **Amener, cas limite** | Cliquer une portion que le replay n'a jamais jouée : la voiture se place au plus proche et le panneau **dit** que le passage n'existe pas. Pas de saut silencieux ailleurs. |
| 23 | **Sonde replay + amener** | Activer le pilotage de replay du panneau de sondes, puis cliquer le ruban : le saut doit tenir, et la sonde ne doit pas ramener le replay en arrière à la frame suivante. |
| 24 | **Noms sur le ruban** | Le segment porte le nom, ou le numéro, ou rien s'il est trop fin — mais celui sous la souris parle toujours. **Double-clic** pour renommer, Entrée valide, Échap abandonne, `Undo` reprend. |
| 25 | Infobulles et aide | Rester sur une valeur : la bulle apparaît après un instant. La ligne du bas nomme ce qui est sous le curseur, tout de suite. Le `?` ouvre la légende. |

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

**Le contrat d'interaction est écrit** : `docs/ui-interactions.md`, rédigé par
le designer d'ATR et adopté tel quel. Il dit ce que l'UI **doit** faire ; ce
fichier-ci dit où on en est. À lire avant de toucher à `apps/lua/CamTool3/ui/`.

Écart restant avec ce contrat, dans l'ordre où il le présente :

| Point du contrat | État |
|---|---|
| Composant paramètre unique, quatre gestes, Ctrl/Shift | ✅ |
| Molette interdite | ✅ |
| Glissé : horizontal, zone morte 4 px, curseur ↔, champ grisé inerte | ✅ |
| Échap pendant un glissé **et pendant une saisie** | ✅ |
| Un glissé = une entrée d'undo, point d'entrée unique | ✅ |
| Losanges à trois états | ✅ |
| **Champ teinté quand le paramètre est animé** | ✅ |
| Infobulle par élément, avec délai | ✅ (délai maison : CSP n'expose pas `DelayNormal`) |
| Ligne de statut contextuelle en bas | ✅ |
| Bouton `?` avec la légende complète | ✅ |
| Supprimer le bloc d'aide du bas | ✅ |
| Colonnes alignées ligne à ligne, largeurs égales | ✅ (`ui.columns`) |
| Bandeau, grisé, carte | ✅ |

⚠️ **Les 32 phrases d'infobulle sont des brouillons.** Elles sont déduites du
code qui implémente chaque paramètre, pas de l'usage : **ATR doit les relire**,
c'est lui qui s'en sert. Elles sont toutes dans `ui/atr.lua`, une par ligne de
`atr.COLUMNS` et `atr.SPLINE` — corriger une phrase est une modification d'une
ligne. Un test vérifie que chaque paramètre en a une, donc un paramètre ajouté
plus tard sans phrase échoue avant d'arriver en jeu.

Deux d'entre elles disent qu'un paramètre **ne fait rien aujourd'hui**, ce qui
est vrai et utile à lire dans la fenêtre :

- `STRENGTH LO.` (`transform_loc_strength`) n'est pas appliqué par le portage.
- `MIX` (`tracking_mix`) n'est **pas appliqué à la visée** : seul l'autofocus
  le lit, pour faire le point sur la voiture la plus proche. Trouvé en
  rédigeant les infobulles. Le mélange de visée entre deux voitures fait
  partie du chantier « smart tracking ».

**Ce que CamTool 2 a et que CamTool 3 n'a pas encore** — la liste qui était
affichée dans la fenêtre, d'où le contrat la chasse :

- enregistrer une spline (par caméra, et celles de piste et de stand) ;
- `load on startup` et les raccourcis (demandent un fichier de réglages que
  CamTool 3 n'a pas) ;
- `Activate Free Camera`.

**Décisions actées avec Théo** (ne pas re-trancher seul) :

- **Une seule UI**, ATR. L'ancienne à onglets n'est pas reproduite.
- **Le losange porte le keyframe** (vide / creux / plein), ce qui libère la
  valeur. Convention des logiciels d'animation, et ça lève l'ambiguïté du
  rouge de CamTool 2.
- **La valeur se glisse** pour scrubber et **se tape** au clavier.
- Couleur saturée en accent d'en-tête seulement ; pastilles en teinte légère.
- **Glisser, jamais la molette** — tranché après un aller-retour avec le
  designer d'ATR. La molette avait été ajoutée puis retirée le lendemain. La
  raison qui l'emporte n'est pas la convention (Blender, Unity, Unreal, After
  Effects, Photoshop, Resolve et `DragFloat` d'ImGui la laissent tous au
  fenêtrage) mais le risque : c'est **le même geste** qu'on veuille défiler ou
  changer une valeur, seule la position du curseur les distingue, et si le
  panneau défile en même temps **les champs passent sous le pointeur** — un
  seul coup de molette touche plusieurs paramètres sans rien signaler. Sur un
  travail dont les erreurs ne se voient qu'au montage, c'est le pire cas.

  Ce qui rend le glissé sûr, et qui est en place : **horizontal uniquement**
  (le vertical rejouerait l'ambiguïté du défilement), **zone morte de 4 px**
  (un clic qui ripe ne change rien), **curseur ↔ au survol** (le seul indice
  que le panneau donne), **Échap** qui remet la valeur de départ, et **un
  glissé = une seule entrée d'annulation** (`edit.continues`, le geste
  identifié par un compteur et non par le nom de la ligne, pour que deux
  glissés du même champ restent deux entrées).
- **La carte se range** (bouton `map`). Elle coûte de la place aux paramètres,
  donc elle doit pouvoir disparaître. Non persistée : CamTool 3 n'a pas encore
  de fichier de réglages.

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
4. ✅ **La mini-carte — faite et validée en jeu sur Spa.** Le tracé du
   circuit dans le panneau ATR, teinté caméra par caméra : `core/trackmap.lua`
   (pur), `adapters/track.lua` (échantillonnage), `ui/map.lua` (dessin).
   Le clic sélectionne la caméra qui couvre le bout de tracé visé ; éditer
   depuis la carte (glisser un `camera_in`) reste à faire.

   **La carte se tourne** pour remplir la bande — l'angle est cherché degré
   par degré sur un demi-tour, et n'est retenu que s'il fait gagner 15 %, donc
   un circuit déjà large garde l'orientation que tout le monde a en tête. Et
   elle prend **la hauteur que sa forme demande**, bornée par un tiers de la
   fenêtre : sur Spa, environ trois fois plus grande qu'au premier jet.

   **Le tracé vient de la spline IA, pas de `map.png`** — tranché avec Théo,
   qui avait proposé d'ouvrir `content/tracks/` et n'en a pas eu besoin.
   `ac.trackProgressToWorldCoordinate` rend le monde depuis une progression
   0..1, donc **chaque point du tracé est une valeur de `camera_in`** : placer
   une caméra est une lecture d'index, pas une inversion de projection, et il
   n'y a ni `map.ini` à décoder ni fichier manquant à gérer. `map.png` reste
   possible plus tard comme fond.

   Ce que ça ne couvre pas : la **voie des stands** (la `fast_lane` s'arrête à
   la piste, donc les caméras `camera_pit` n'ont pas de support — à relier au
   chantier « caméras de stand »), et les circuits **sans `fast_lane.ai`**
   (drift, gymkhana, certains layouts secondaires), où la carte le dit et
   s'abstient. À relativiser : la sélection de caméra lit déjà
   `car.splinePosition`, donc un circuit sans spline est un circuit où l'app
   ne fait rien de toute façon.

5. ✅ **La bande de piste — faite, jamais vue en jeu.** Un ruban 0 → ligne
   d'arrivée (`ui/band.lua`), teinté par caméra, les keyframes de la caméra
   éditée en losanges, la voiture en trait vertical. Cliquer une portion
   sélectionne sa caméra, cliquer un losange sélectionne le keyframe.

   Même propriété que la carte, projetée sur une ligne — d'où
   `trackmap.bandSpans`, qui ne diffère que sur le bouclage : la caméra qui
   tient la ligne d'arrivée est **dessinée aux deux bouts**, puisqu'un ruban
   droit ne peut pas boucler comme un tracé.

   Passe à l'échelle de l'issue **#6** : un ruban se moque du nombre de
   caméras là où la grille donne une cellule à chacune, vingt par ligne.

   ⚠️ **Un interrupteur temporaire, `[strips]`, masque les deux bandes
   numérotées.** Ce n'est pas une option et ça ne doit pas le devenir : c'est
   l'outil pour répondre par l'usage à « le ruban les a-t-il rendues
   inutiles ». Marche à suivre, proposée par le designer d'ATR et retenue :
   les masquer, **préparer les caméras d'une vraie vidéo**, et voir si elles
   manquent. Puis l'interrupteur disparaît, dans un sens ou dans l'autre —
   le garder voudrait dire maintenir deux interfaces pour toujours.

   La raison de ne pas sortir une version puis retirer les bandes à la
   suivante : ça ferait apprendre le panneau deux fois.

   `Starting point` et la ligne `KEYFRAME` restent, et c'est voulu : le ruban
   donne le geste, ces champs donnent la valeur au mètre près.
6. ✅ **Éditer depuis la carte et depuis la bande — fait, jamais vu en jeu.**
   La caméra sélectionnée porte une **poignée** là où elle prend le relais :
   un point sur le tracé, un trait sur le ruban. La glisser déplace son
   `camera_in`.

   Une seule poignée, celle de la caméra choisie : sur un set de cent, une
   poignée par caméra serait un collier de points, et déplacer la mauvaise est
   une erreur qui ne se voit qu'au montage. **L'appui doit commencer dessus** —
   un glissé parti d'ailleurs ne l'attrape pas au passage, sinon cliquer pour
   sélectionner déplacerait la caméra sélectionnée. Les deux règles ont leur
   test de morsure.

   **Trouvé en câblant : `camera_in` n'avait aucun chemin d'édition.** La ligne
   `STARTING POINT` s'affichait, et ses flèches, son glissé et sa saisie ne
   faisaient rien — la boucle de dispatch ne traite que les clés de
   `edit.RULES`, où `camera_in` ne figurait pas. Il y est maintenant, avec un
   pas d'un millième de tour (≈ 5 m sur un circuit normal, et qui suit la
   longueur du circuit plutôt que d'être 5 m partout).

   ⚠️ **Un `camera_in` ne peut plus croiser ses voisins**
   (`edit.betweenNeighbours`). La liste est triée par `camera_in` et tout en
   dépend : la sélection la parcourt dans l'ordre, et les deux projections
   découpent leurs segments sur des débuts consécutifs. Croiser casserait les
   trois en silence. Une caméra s'arrête donc à sa voisine au lieu d'échanger
   de place — échanger voudrait dire renuméroter en plein geste, et la caméra
   tirée changerait d'index sous la main qui la tire.

**Nommer les caméras — fait** (version 2 pour les données, plus haut). Le
segment du ruban porte le nom s'il tient, le numéro s'il n'y a place que pour
lui, rien du tout s'il est trop fin — sauf celui **survolé ou sélectionné**,
qui dit qui il est en empruntant la place de ses voisines. C'est ce qui garde
un set de cent caméras lisible au lieu d'une rangée de moignons.

**Double-clic sur un segment pour renommer sur place.** Le renommage est tenu
par l'**`id`**, pas par le rang : insérer une caméra pendant qu'on tape décale
le rang sous le champ, et un renommage qui suivrait le rang atterrirait sur la
mauvaise caméra. Un test le prouve. Échap abandonne, comme partout ailleurs
dans le panneau.

**Les losanges ne se glissent PAS** — retiré à la demande de Théo après essai.
Un losange fait quatre pixels sur un ruban qu'on clique aussi pour sélectionner
une caméra : un clic légèrement raté déplaçait un keyframe, et un keyframe
déplacé par mégarde ne se voit qu'au montage. Ils se déplacent depuis le champ
`KEYFRAME`, où le geste ne peut pas être confondu. La poignée de caméra, elle,
reste glissable : c'est une prise délibérée sur un repère marqué.

**Le clic droit ouvre un menu** : « ajouter une caméra ici », « supprimer cette caméra ». La position
vient de l'endroit du clic droit, pas de la tête de lecture — un `+` doit
décider à ta place où va la caméra, un clic droit l'a déjà dit. Et une
suppression derrière un menu ne s'atteint pas par mégarde, ce qui compte plus
ici qu'un clic épargné : le `−` de la bande numérotée est collé à son `+`.

**Les noms de virages marchent** — vérifié en jeu par Théo sur Spa :
`ac.getTrackSectorName` lit bien le `sections.ini` du circuit et rend
« Kemmel Straight », « Les Combes ». La sonde qui a servi à le confirmer reste
dans le panneau de diagnostic (section « 11 »).

Renommer une caméra **sans nom** propose donc celui de l'endroit où elle se
tient. Proposé, jamais imposé : le champ sélectionne tout, donc la première
frappe l'efface et Échap abandonne.

⚠️ **Les sections ne couvrent pas tout le tour.** Sur la lecture de Spa,
`0.00` et `0.12` reviennent vides là où `0.25` donne « Kemmel Straight ».
`track.sectionNameAt` rend donc `nil` et pas `""` : une caméra sur une portion
que personne n'a nommée ouvre un champ vide, pas un blanc qui ressemble à un
nom. **`sections.ini` du circuit** définit des
`IN` / `OUT` / `TEXT` (« Tamburello »), et `ac.getTrackSectorName(progress)`
de CSP lit très probablement ce fichier — à vérifier en jeu avant de le
promettre. Ça donnerait un nom automatique neutre du type « 14 — Tamburello »
pour qui pose quarante caméras sans en nommer une seule.

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

### Version 2 : une caméra qui garde son identité

Ajoutée avec le chantier du ruban, sur l'analyse du designer d'ATR et vérifiée
dans le code : **le numéro affiché est le rang dans la liste, et le rang
bouge.** `edit.addCamera` ajoute puis trie par `camera_in`, donc insérer une
caméra entre la 5 et la 6 décale tout ce qui suit — « caméra 14 » devient 15,
et avec elle chaque note et chaque repère mental.

CamTool 2 a l'air d'avoir résolu ça : chaque caméra porte un `slot`. Mais
`sort_cameras` fait `slot = i` à chaque tri
([data.py:455](../apps/python/CamTool_2/classes/data.py)). C'est un rang mis en
cache, pas une identité. **Il n'existait donc aucun identifiant stable.**

- **`id`** — pour le programme. Ne change jamais, ne se répète jamais, survit
  au tri, au renommage et à la sauvegarde. Le compteur `next_camera_id` vit
  **sur le document** : le déduire des caméras présentes redonnerait au
  prochain ajout l'`id` de la dernière supprimée.
- **`name`** — pour l'utilisateur, **facultatif**. Un fichier où personne n'a
  rien nommé est parfaitement normal : `data.cameraLabel` retombe sur le rang.
  Le rang reste ce qu'un raccourci vise et ce que deux personnes se disent à
  propos d'un bug.

La migration est à sens unique comme les autres, et un fichier v2 sans `id`
est **réparé** plutôt que cru.

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

   **La sixième caméra de la famille F1 existe**, bien que
   `ac.DrivableCamera` n'en nomme que cinq : `steering wheel` et `cockpit`
   donnent bien deux vues différentes, vérifié en jeu. Voir `docs/legacy.md`.

   Passer la main = demander la caméra **et** cesser d'écrire le transform :
   `ownShare` à 0 laisse passer la vue d'AC à travers le grab qu'on garde,
   donc reprendre la main est juste le remettre. Le changement se fait au
   changement, pas à chaque frame, pour ne pas se battre avec quelqu'un qui
   appuie sur F1.
5. **L'UI** (maquette ATR) — le gros du travail, sans risque technique connu.
   La carte est faite ; restent la bande de piste et l'édition depuis la carte
   (voir la liste ordonnée de la section UI).
6. **L'écriture de fichiers** — jusqu'ici volontairement hors périmètre. Voir la
   migration à sens unique dans `docs/legacy.md` : on écrit toujours le format v1.

### Réserves connues, non bloquantes

- **Les champs sont vides tant qu'aucune caméra n'est choisie.** `atrCamera`
  retombe sur `pbOut.activeCam`, qui n'existe que **caméra prise** (le calcul de
  lecture sort tôt si la caméra n'est pas tenue). Sans ça, tous les champs
  affichent `--` et aucun geste n'a de prise. Cliquer une caméra dans la bande
  ou sur la carte les remplit, même sans prendre la caméra. À trancher : est-ce
  qu'ouvrir un fichier devrait suffire à voir la caméra 1 ?

- **Mouse look** : la visée est moins douce que dans CamTool 2. La cause est
  identifiée : le legacy pilote la caméra avec la **moyenne des 60 dernières
  positions de souris**, et le bouton gauche commande le remplissage de ce
  tampon — le relâcher laisse la caméra finir sur son élan. Le portage envoie le
  delta brut. Reproduire la moyenne glissante, pas un lissage exponentiel (voir
  `docs/ui-inventory.md`).
- **`transform_loc_strength`** n'est pas appliqué (il vaut 1.0 sur les 566
  caméras de référence et n'est jamais keyframé, donc sans effet aujourd'hui).

## 🎯 Amener la voiture depuis le ruban — branche `replay-seek`

Clic simple sur le ruban : sélectionne la caméra **et** déplace le replay pour
que la voiture soit à l'endroit cliqué. **Maj+clic** sélectionne sans toucher
au replay. Le menu du clic droit porte « Bring the car here » en toutes
lettres, et la ligne de statut annonce les deux gestes au survol — sans coûter
un pixel de hauteur.

**Le pont entre les deux mondes.** Le ruban parle en positions de piste, un
replay s'adresse par numéro de frame, et rien dans le jeu ne convertit. Mais
l'app lit déjà les deux côte à côte à chaque frame : `core/seek.lua` écrit la
correspondance au fil de l'eau. Un casier par position quantifiée (1024, soit
≈ 6,8 m sur Spa), les dernières frames où la voiture y est passée. Coût par
frame : un multiply, un floor, une écriture. **Aucune allocation**, taille qui
ne peut pas croître, index vidé si le replay ou la voiture change.

**Plusieurs frames par casier, et c'est tout l'enjeu.** Un replay, ce sont des
tours sur les mêmes positions : « amener la voiture ici » veut dire le passage
**le plus proche dans le temps**, jamais le premier tour. Une frame par casier
répondrait toujours le premier — ce qui a l'air juste sur un replay d'un tour
et renvoie au début sur tous les vrais.

**Zone jamais jouée** : estimer, sauter, lire l'écart, corriger, cinq essais au
plus. Chaque sondage enrichit l'index. Sans convergence, on reste **au plus
proche atteint** et la ligne de statut le dit — jamais de saut silencieux.

**Deux pièges trouvés par les tests, pas par la lecture :**

- **Le plus court chemin n'est pas toujours disponible.** Près du début d'un
  replay, le passage le plus proche est souvent *avant* la frame zéro ; borner
  à zéro laissait la recherche collée contre le mur à se répéter. Quand le
  court chemin sort du replay, on prend le long, qui est le même endroit un
  tour plus tard.
- **Une voiture à l'arrêt** occupe des milliers de frames dans un casier : un
  seul passage, une seule entrée, sinon elle chasse tous les vrais tours.

**Ce que ça ne fait pas** : aucune entrée d'annulation. Déplacer le replay
n'est pas une modification de données.

Le son est coupé pendant les sauts (CamTool 2 avait des artefacts sur les
changements de position), sauf si la sonde audio tient déjà le volume.

## Idées notées, pas tranchées

- **Une voiture par caméra.** `ACTIVE CAR` est aujourd'hui une ligne *runtime* :
  elle montre `sim.focusedCar`, la voiture que le replay suit globalement, et
  aucun fichier n'en mémorise une — c'est l'état de session hérité de
  CamTool 2, remis à la voiture 0 à chaque lancement.

  La question s'est posée en spécifiant « amener la voiture à l'endroit
  cliqué » : viser « la voiture de la caméra sélectionnée » supposerait ce
  champ. Théo a retenu la voiture focalisée, qui revient au même aujourd'hui,
  **en notant qu'on pourra regarder la voiture par caméra plus tard**. Ce
  serait une vraie fonctionnalité : un champ de plus dans le fichier, donc une
  version de schéma, et une ligne de plus dans le panneau.

## Décisions tranchées (ne pas rouvrir seul)

Ces quatre-là ont été listées comme ouvertes, puis fermées par Théo. Gardées
ici avec leur raison, parce qu'une question fermée sans trace se repose.

- **Le dépôt reste dans le dossier du jeu.** Pas de jonction Windows, pas de
  déplacement. On laisse comme ça.

- **`interpolation_mode` reste par fichier.** Le passer par caméra permettrait
  de mélanger anciennes et nouvelles caméras dans un même set : aucun intérêt
  pratique, et ça doublerait le nombre d'états à tenir en tête.

- **#23 n'était plus une décision ouverte, juste une entrée périmée.** Le
  correctif n'est plus derrière une case à cocher depuis que
  `playback.applyMode` dérive les deux interrupteurs de `interpolation_mode`.
  Le comportement actuel, qui convient :

  | Fichier | Mode | #23 |
  |---|---|---|
  | CamTool 2 migré | `legacy` (`data.lua:96`) | garde le bug |
  | Écrit par CamTool 3 | `fixed` (`data.lua:121`) | corrigé |

  Et le panneau affiche le mode et permet d'en changer volontairement. Un
  montage déjà fait ne bouge donc pas, un set neuf n'hérite pas du bug.

- **Le bug `SolveCubic` reste tel quel, dans les deux modes.** C'est le point
  qui demandait une vérification : il n'a jamais été corrigé nulle part.
  `solveCubic` ne prend pas de mode, le bug est reproduit inconditionnellement,
  et `fixed` ne le touche pas. Le comportement actuel convient, donc on n'y
  touche pas.

  ⚠️ **Conséquence à connaître : `fixed` ne veut pas dire « tout corrigé ».**
  Il couvre exactement deux choses, `legacyLastCamera` (#23) et
  `legacyZeroFill` (#16). Les deux bizarreries du solveur — **#1** (`SolveCubic`
  rend `nil` sur racine double, la caméra garde sa valeur de la frame
  précédente) et **#4** (`SolveQuadratic(0, 0, c)` rend la constante) — sont
  reproduites dans les deux modes. Le registre de `docs/legacy.md` les décrit ;
  ce qui suit dit simplement qu'aucune n'est branchée sur le mode.
