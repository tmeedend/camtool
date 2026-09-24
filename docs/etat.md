# Où on en est

> **À lire en premier en reprenant le projet.** Ce fichier bouge à chaque
> avancée. Les règles et contraintes sont dans `CLAUDE.md`, le savoir accumulé
> sur CamTool 2 dans `docs/legacy.md`.

## État des branches

| Branche | Rôle |
|---|---|
| `main` | **CamTool 3, et la seule branche de travail.** Tout y est intégré au fil de l'eau. |
| `poc/lua` | Le POC qui a fondé la décision Lua. Conservée comme repère, figée. |
| `develop`, `feature/*` | Antérieures au projet CamTool 3. |

⚠️ **Ce tableau disait le contraire jusqu'ici** — « `main` : CamTool 2 en
production » — et c'était faux depuis longtemps : `main` portait déjà plus de
cent commits de CamTool 3 en local. Le correctif 2.x n'a plus de branche
dédiée ; s'il en faut un, il part du dernier commit CamTool 2 de l'historique.

Validation avant toute modification, depuis `apps/lua/CamTool3/` :
`luajit tests/run.lua` (720 tests au dernier point). Le binaire n'est pas dans
le `PATH` des sessions d'outillage : voir `CLAUDE.md`.

## ✅ Décision actée : CamTool 3 sera une app Lua CSP

Tranché par Théo après le POC (branche `poc/lua`, conservée comme repère). Le développement continue sur `main`, dans `apps/lua/CamTool3/`.
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
| 15 | **Bande de piste** | Le ruban sous les bandes numérotées : une teinte par caméra, les losanges de la caméra éditée, la tête de lecture. Cliquer une portion sélectionne sa caméra — et **ne doit rien déplacer** —, cliquer un losange sélectionne le keyframe. |
| 16 | **Poignée de `camera_in`** | La caméra sélectionnée porte une poignée (point sur la carte, trait sur le ruban). La glisser déplace son début. Elle doit **buter** sur les caméras voisines. Un `Undo` annule **tout le glissé**, pas une frame. |
| 17 | `STARTING POINT` | Ses flèches, son glissé et sa saisie marchent **enfin** — ils ne faisaient rien jusqu'ici. Un pas ≈ 5 m. |
| 18 | **Infobulles** | Rester sur une valeur : la phrase apparaît après un instant. Elles **ne marchaient pas du tout** — le panneau reconstruisait la ligne et laissait la phrase en route. |
| 19b | **Relâcher puis voler** | `Take camera` sur une caméra, `Release camera`, puis voler ailleurs : `X`, `Y`, `Z` doivent **suivre la vue**, pas rester figés sur le plan qu'on vient de quitter. La tête de lecture doit continuer à suivre le replay, et **aucun** segment du ruban ne doit rester pâle. |
| 19 | **Champs en caméra libre** | Voler en caméra libre : `X`, `Y`, `Z`, `PITCH`, `HEADING`, `FOV` doivent afficher la valeur **en gris**, et le losange l'épingler telle quelle. `ROLL` et `FOCUS POINT` restent à `--`, c'est voulu. |
| 20 | **Créer un fichier** | Session neuve, **double-clic sur « no file »**, taper un nom, Entrée. Puis `+cam` doit marcher. Le fichier doit apparaître dans la liste avec le préfixe de la piste. |
| 21 | **Sauver sous un nom** | Fichier d'ATR chargé, **double-clic sur son nom** : le champ doit s'ouvrir **et rester ouvert** (il se refermait aussitôt). Taper, Entrée. L'original ne doit pas changer de date. |
| 22 | **Raccourcis** | Par défaut **aucune touche**. Voler en caméra libre aux flèches ne doit plus rien déplacer dans le panneau. Affecter une touche dans `?` → SHORTCUTS : elle parcourt les keyframes ou les caméras, la tête de lecture suit, et aux extrémités ça s'arrête. Les anciennes entrées `camtool3/Next keyframe` et les variantes Maj restent dans `controls.ini` et ne doivent rien faire. |
| 23 | **Le piège du clavier** | **Taper une valeur ou nommer une caméra, avec Espace et les flèches** : ça doit écrire et déplacer le curseur, jamais piloter le panneau. |
| 24 | **Réaffecter une touche** | Panneau `?` → SHORTCUTS → changer une touche, vérifier qu'elle prend effet et qu'elle survit à un redémarrage (elle est dans `controls.ini`). |
| 25 | **Indicateur ▶ / ⏸** | Mettre le replay en pause **depuis la barre d'AC** : l'icône doit suivre. Elle ne doit pas clignoter au ralenti. |
| 26 | **Annuler un geste** | **Clic droit** pendant un glissé remet la valeur de départ. **Cliquer ailleurs** abandonne une saisie. Échap ne doit **plus rien** faire dans le panneau — il quitte le replay, comme toujours. |
| 27 | **Ruban, édition** | **Clic droit** sur un segment : ajouter une caméra ici, supprimer celle-ci. Glisser la poignée = **une** entrée d'`Undo`. Un losange ne doit **pas** bouger. |
| 28 | **Nom suggéré** | Double-clic sur une caméra sans nom, sur une portion nommée du circuit : le champ s'ouvre **prérempli** (« Les Combes »). Sur une portion sans nom : champ vide. Taper efface la suggestion. |
| 29 | **Carte à l'endroit** | Un virage pris à gauche doit pencher à gauche sur la carte. La carte était en miroir. |
| 30 | **Règle = amener la voiture** | Cliquer **la règle** doit déplacer le replay à cet endroit précis, **sur le tour le plus proche** et pas au premier. Le son ne doit pas claquer. |
| 31 | **Amener, cas limite** | Cliquer une portion que le replay n'a jamais jouée : la voiture se place au plus proche et le panneau **dit** que le passage n'existe pas. Pas de saut silencieux ailleurs. |
| 32 | **Sonde replay + amener** | Activer le pilotage de replay du panneau de sondes, puis cliquer la règle : le saut doit tenir, et la sonde ne doit pas ramener le replay en arrière à la frame suivante. |
| 33 | **Noms sur le ruban** | Le segment porte le nom, ou le numéro, ou rien s'il est trop fin — mais celui sous la souris parle toujours. **Double-clic** pour renommer, Entrée valide, Échap abandonne, `Undo` reprend. |
| 33b | **Renommer une caméra** | Double-clic sur un segment : le champ doit s'ouvrir **avec le curseur dedans** — taper doit écrire tout de suite. Cliquer ailleurs le referme, y compris sur une caméra qui n'avait aucun nom. |
| 33c | **Nom de fichier** | Le bandeau du haut n'affiche que le nom (`theo`), sans `spa_-` ni `.json`. Double-clic, taper `theo`, Entrée : le fichier apparaît **sélectionné**, sans toucher aux flèches. Retaper `spa_-theo.json` en entier doit donner le même fichier, pas un doublon. |
| 33d | **Créer en partant de rien** | Session neuve, replay lancé, **`+cam` directement** : une caméra doit naître et le bandeau dire « unsaved set ». `Save` doit alors **ouvrir le champ de nom**, pas refuser. |
| 33e | **Plus d'infobulles** | Survoler n'importe quoi : **aucune bulle** ne doit apparaître. La phrase et les gestes sont dans la ligne du bas. |
| 33f | **Bouton `keys`** | À côté du `?`. Il ouvre les affectations seules ; ouvrir l'un doit refermer l'autre. |
| 33g | **Numéros et noms** | Les segments ne portent que des **chiffres**, jamais un nom, même quand un nom tiendrait. Survoler un segment **ou un point du tracé** : la ligne du bas dit « Camera 4 — Fagnes ». Un segment trop fin pour un chiffre reste visible et se nomme au survol. |
| 33h | **Charger par-dessus du non sauvé** | Faire une modification, puis cliquer le nom de fichier : le bouton doit devenir `lose changes? …` et **ne rien charger**. Un second clic charge. Passer la souris sur le ruban entre les deux ne doit **pas** annuler la question. Sans modification en cours, aucune question. |
| 33i | **#16, caractériser** | Pas une vérification : une **mesure**. Prendre la caméra dix fois de suite en notant à chaque essai la caméra AC active avant, si le replay tournait, l'erreur de relecture du panneau de sondes, et glissement oui/non. Le tableau vaut mieux que n'importe quelle relecture de code — voir la section #16. |
| 34 | Légende `?` | Rester sur une valeur : la bulle apparaît après un instant. La ligne du bas nomme ce qui est sous le curseur, tout de suite. Le `?` ouvre la légende. |
| 35 | **La règle** | Le bandeau du haut se distingue du reste au premier coup d'œil. Les distances sont lisibles et ne se chevauchent pas ; **redimensionner la fenêtre** doit en ajouter ou en retirer, jamais les entasser. Sur Spa, « Kemmel Straight » et « Eau Rouge » doivent s'afficher à leur place. |
| 36 | **Scrub** | Presser la règle et **glisser sans lâcher** : l'image doit suivre la main, un peu en retard mais en continu, sans à-coup ni saut en arrière. Au relâchement, la voiture se pose **exactement** où le trait a été lâché. |
| 37 | **Le son pendant un scrub** | Le son se coupe **au début** du glissé et revient **une fois** à la fin — pas de hachis, pas de retour du son au milieu du geste. |
| 38 | **Curseurs des deux zones** | Le pointeur change de forme au-dessus de la règle (flèche horizontale) et au-dessus des segments (main). La ligne de statut dit deux choses différentes selon la zone. |
| 39 | **Sélection sans déplacement** | Cliquer un segment pendant que le replay tourne : la caméra change dans le panneau et **l'image ne bouge pas**. Même chose sur la carte. Avec Maj aussi : Maj ne doit plus rien changer. |
| 40 | **Circuit sans `sections.ini`** | Sur un circuit ou un layout mod qui n'en a pas, la règle doit montrer les distances seules, sans erreur ni trou dans le panneau. |

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

Une d'entre elles dit qu'un paramètre **ne fait rien aujourd'hui**, ce qui
est vrai et utile à lire dans la fenêtre :

- `STRENGTH LO.` (`transform_loc_strength`) n'est pas appliqué par le portage.

`MIX` était le second cas : **fait, à confirmer en jeu** (`core/cars.lua`, et
le mélange dans `core/playback`). Ce n'est pas du smart tracking : CamTool 2
l'applique hors smart tracking (`InterpolateFrame.py` ~243-255). La visée vers
`EXTRA CAR`, avec la même avance, est mélangée à celle vers la voiture active
au prorata de `MIX` ; l'autofocus fait le point sur la plus proche des deux.
Les flèches de `ACTIVE CAR` et `EXTRA CAR` marchent comme dans CamTool 2 :
voiture précédente ou suivante **sur la piste**, et `ACTIVE CAR` déplace le
replay (`ac.focusCar`). Les deux lignes affichent le nom du pilote.

Tranché avec Théo : l'extra car reste un **état de session**, comme dans
CamTool 2 (un numéro de voiture n'a de sens que dans un replay, et un fichier
caméra sert à tous ceux d'une piste) ; et elle part de **aucune** au lieu de
la voiture 0, qui est si souvent la voiture suivie que `MIX` ne faisait rien
sans dire pourquoi. Deux défauts de CamTool 2 ne sont pas reproduits : #9 et
#10 du registre de `docs/legacy.md`. L'autre piste, « la voiture juste
devant » définie par rapport à la voiture suivie, reste à voir avec ATR.

**Ce que CamTool 2 a et que CamTool 3 n'a pas encore** — audit du
2026-09-24, fait en reprenant `docs/ui-inventory.md` ligne à ligne et la
boucle `acUpdate` de CamTool 2. Théo ne veut pas de bêta avec une
fonctionnalité manquante : cette liste doit être vide avant la sortie. Dans
l'ordre de traitement retenu :

1. **Les caméras de stand ne sont pas éditables.** On ne choisit une caméra
   qu'au ruban ou à la carte, et les deux ne montrent que les caméras de
   piste : une caméra `PIT ONLY` n'est joignable que quand elle joue, et
   cocher `PIT ONLY` la fait disparaître du ruban. CamTool 2 les listait
   toutes.
2. **Le fondu du son aux coupes** — absent de l'inventaire, trouvé dans
   `acUpdate` (`CamTool_2.py` ~116-132) : à chaque changement de caméra ou de
   voiture suivie, le volume repart de zéro et remonte en 0,5 s (courbe
   quadratique).
3. **`Activate Free Camera`** (bouton de l'en-tête).
4. **`Load on startup`** : recharger le dernier fichier utilisé.
5. **Supprimer un fichier** de la liste (le `✕`), à demander deux fois comme
   `Reset`.
6. **Les touches** : F10 active, F1/F2/F3/F5/F6/F7 (caméras d'AC) désactivent,
   Y/U/I/O/P chargent les fichiers 1 à 5 derrière `Enable hotkeys`.
7. **Le mode temps** : la liste `time` s'édite mais se joue sur la position de
   la voiture ; CamTool 2 la joue sur le temps du replay
   (`replay.get_interpolated_replay_pos`). Unité de `camera_in` à établir.
8. **Enregistrer une spline** : par caméra (onglet Spline), et les splines de
   piste et de stand (onglet Settings), `Record → Stop → Remove`. Le plus
   gros morceau : portage de `record_spline`.
9. **Reset de `PITCH` et `ROLL`** : taper `0` fait déjà la même chose ; à
   trancher avec Théo s'il faut un geste dédié.

Vu en passant : la légende du `?` parle encore d'une « Camera strip » que le
ruban a remplacée.

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
   d'arrivée (`ui/band.lua`), en **deux zones** : une règle fine en haut
   (distances, noms de portions, tête de lecture) et en dessous les segments,
   teintés par caméra, avec les keyframes de la caméra éditée en losanges.
   Cliquer une portion sélectionne sa caméra — sans rien déplacer —, cliquer
   un losange sélectionne le keyframe. Voir « Le ruban navigable » plus bas.

   Même propriété que la carte, projetée sur une ligne — d'où
   `trackmap.bandSpans`, qui ne diffère que sur le bouclage : la caméra qui
   tient la ligne d'arrivée est **dessinée aux deux bouts**, puisqu'un ruban
   droit ne peut pas boucler comme un tracé.

   Passe à l'échelle de l'issue **#6** : un ruban se moque du nombre de
   caméras là où la grille donne une cellule à chacune, vingt par ligne.

   ✅ **Les deux bandes numérotées sont supprimées**, et l'interrupteur
   temporaire avec. Décidé comme le designer l'avait proposé : masquées
   derrière un interrupteur, une session de vrai travail, et elles n'ont pas
   manqué. Rien n'a été retiré sur un argument.

   Où est passé ce qu'elles portaient : **sélectionner** une caméra ou un
   keyframe est un clic sur les segments du ruban, **ajouter et supprimer une caméra** est
   son menu au **clic droit** — il n'y a plus de bouton, et Théo ne l'a pas
   trouvé, parce que la légende et la ligne de statut disaient « right click
   for more », ce qui ne nomme rien. Elles nomment les trois entrées
   maintenant. La paire de boutons keyframe a rejoint la rangée d'actions — un keyframe naît à la tête de lecture sur la caméra
   sélectionnée, donc ni l'un ni l'autre n'a besoin d'un endroit à viser.

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

### ⚠️ La carte n'inverse PAS l'axe vertical

Elle l'a fait, sur le raisonnement que l'écran grandit vers le bas alors que le
monde non. Juste pour un monde droitier ; celui d'Assetto Corsa est **gaucher**,
donc la carte sortait **en miroir** — un virage pris à gauche penchait à droite
à l'écran. Théo l'a vu tout de suite, et c'est la seule façon dont ça pouvait se
trancher : le raisonnement est précisément ce qui s'est trompé.

Le test ne demande donc pas « où est le nord » mais **si le dessin tourne dans
le même sens que la piste** — le signe de la transformation, vérifié aussi à
plusieurs angles de rotation.

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
2. ~~**Caméras de stand**~~ — **fait, à confirmer en jeu** (`core/pitlane.lua`).
   Voiture aux stands : seconde passe de sélection sur les seules caméras de
   stand, la caméra de piste reste si le fichier n'en a aucune. « Aux stands »
   se décide comme dans le legacy : par les `track_spline` et `pit_spline` du
   fichier quand il a les deux (c'est le cas de Red Bull Ring), sinon par
   `car.isInPitlane` de CSP. Un écart assumé avec Théo, la « dernière caméra »
   (#8 du registre de `docs/legacy.md`). Le balayage, qui roule sur la piste,
   ne voit toujours que 9 caméras sur 11 à Red Bull Ring : c'est normal.
   La **carte** et le **ruban** ne montrent encore que les caméras de piste.
3. ~~**Smart tracking**~~ — **rien à porter : la fonctionnalité est morte dans
   CamTool 2.** L'idée : quand un adversaire passe à moins de 50 m de la
   voiture suivie, décaler la visée entre les deux et ouvrir le FOV pour
   cadrer le duel, avec 2,5 s de transition d'un adversaire à l'autre. Mais :
   - son seul interrupteur est commenté (`ui/settings_layout.py` ~40 et ~47),
     et `data.smart_tracking` part à `False` sans que rien le change ;
   - activé, il lèverait aussitôt : `update_smart_tracking_values` lit un `x`
     qui n'existe pas (`Camera.py` ~190, le paramètre s'appelle `the_x`),
     avalé par `debug(e)` ;
   - `calculate_cam_rot_to_smart_tracking_car` n'est appelée nulle part.

   Aucun utilisateur ne l'a donc jamais eu. Le refaire serait une
   **fonctionnalité nouvelle à concevoir** (réglages à trouver en jeu, place
   dans l'UI, avis d'ATR), pas un rattrapage. Tranché avec Théo : hors release.
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

- ~~**Mouse look**~~ — **porté, à confirmer en jeu** (`core/mouselook.lua`).
  La note qui était ici décrivait la sonde 11 de la fenêtre de développement,
  absente du zip : le vrai mouse look n'existait pas du tout pour
  l'utilisateur. Il couvre les deux cas de CamTool 2 : caméra tenue (la
  lecture du fichier cède la main en 1 s et la reprend en 2 s, position figée,
  mise au point à 300 m, shake atténué) et **caméra libre d'AC** sans rien
  tenir (orientée par `ac.setCameraDirection` / `ac.setCameraFOV`). Moyenne
  glissante sur 60 échantillons, élan au relâchement, zoom Shift/Ctrl adouci.

  Tranché avec Théo : touches **Alt / Shift / Ctrl par défaut**, réaffectables
  (seule exception à « aucune touche par défaut ») ; calcul **calé sur le
  temps**, pas sur les frames ; un clic sur une fenêtre ne tourne pas la
  caméra. **Premier point à vérifier en jeu** : que `ac.ControlButton` accepte
  un modificateur seul, et signale Shift quand Alt est déjà enfoncé — la
  sonde « 9. Modifier keys » affiche maintenant les trois états vus par les
  raccourcis à côté des états bruts.
- **`transform_loc_strength`** n'est pas appliqué (il vaut 1.0 sur les 566
  caméras de référence et n'est jamais keyframé, donc sans effet aujourd'hui).

## 🎯 Le ruban navigable — branche `replay-seek`

**Deux zones, et le fond les distingue.** Une règle fine en haut — distances
sur le tour, noms des portions quand le circuit en donne — et en dessous les
segments de caméra comme avant. Le fond de la règle est ce qui fait le
travail : il rend la coupure évidente sans un mot, ce qu'une coupure expliquée
n'obtient jamais. Elle fait 16 px et non la dizaine demandée, parce qu'une
ligne de texte en fait 13 et qu'une règle où l'on ne peut pas écrire une
distance est une rangée de marques qui ne mesurent rien.

**Un nom l'emporte sur un chiffre.** Les deux ne tiennent pas sur la même
ligne : là où le circuit a nommé la portion, la distance abandonne son
étiquette et garde sa marque. On lit le chiffre sur les marques voisines,
c'est à ça qu'une règle sert.

**Les noms viennent du fichier, pas d'une sonde.** `ac.getTrackSectorName`
répond position par position ; la règle dessine un nom **en travers** de la
portion qu'il couvre, donc il lui faut les bornes. `core/sections` fait le
ménage dans ce que `ac.INIConfig.trackData('sections.ini')` rend : bornes à
l'envers, nom fait de trois espaces, portion à cheval sur la ligne (coupée en
deux, comme la caméra qui tient la ligne), valeur qui n'est pas un nombre.
Fichier lu une fois par circuit.

**La tête de lecture** traverse les deux zones, avec une poignée triangulaire
dans la règle. Elle suit le replay toute seule. On la déplace en cliquant ou
en glissant **n'importe où sur la règle** — viser cinq pixels de triangle
avant que quoi que ce soit ne bouge est une épreuve d'adresse, pas un geste.
Un clic est un glissé d'une frame, donc les deux sont le même code.

**Le glissé est volontairement grossier** : un saut toutes les 100 ms, une
seule sonde, aucune convergence. La recherche ordinaire sonde à **chaque
frame** jusqu'à tomber juste — soit soixante repositionnements par seconde
pendant un glissé, et pour rien, puisque le pointeur a bougé entre temps. Un
atterrissage faux reste en place jusqu'au tick suivant ; d'ici là la boucle de
frame a noté où on avait atterri, donc la correction est mieux informée qu'une
seconde sonde ne l'aurait été. **L'atterrissage exact a lieu une fois, au
relâchement.** Le son est coupé pour tout le geste, pas par saut — ce pour
quoi le volume est sorti du `seekJob`.

**Le clic ne déplace plus le replay, et Maj non plus.** L'état antérieur
faisait clic = sélectionner *et* amener la voiture, Maj+clic pour s'en
abstenir. Tranché par Théo : déplacer le replay à chaque sélection gêne la
création de caméras — choisir une caméra à éditer n'est pas demander à aller
la regarder — et un modificateur caché n'est connu que de son auteur. La
carte suit la même règle : elle doit dire la même chose que le ruban ou
aucune des deux ne peut être crue. « Bring the car here » reste au menu du
clic droit, en toutes lettres.

**Le double-clic garde partout le même sens : éditer le texte de l'élément.**
Sur un champ, la valeur ; sur un segment, le nom. C'est la convention
universelle, du gestionnaire de fichiers aux calques de Photoshop — donc pas
de « double-clic = aller au début de la caméra », d'autant que le geste est
déjà couvert deux fois, par Haut/Bas et par le menu du clic droit.

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

**Échap est laissé au jeu.** Il quitte le replay, et l'app *peut* le retenir
(`ui.captureKeyboard`, essayé et fonctionnel) — mais retenir la touche entraîne
la main à la chercher, dans une application où la même touche, un instant plus
tard sans champ ouvert, met fin à la session **avec toutes les caméras non
sauvegardées**. Un geste d'annulation ne vaut pas ce risque : tranché par
Théo. On annule un glissé au **clic droit**, une saisie en **cliquant
ailleurs**. Écart assumé avec le contrat du designer, noté dedans.

**Ce que ça ne fait pas** : aucune entrée d'annulation. Déplacer le replay
n'est pas une modification de données.

Le son est coupé pendant les sauts (CamTool 2 avait des artefacts sur les
changements de position), sauf si la sonde audio tient déjà le volume.

## ⌨️ Raccourcis clavier et indicateur de lecture

**Les raccourcis** parcourent les keyframes et les caméras, et **déplacent
la tête de lecture** — exactement les touches de
saut d'un point de montage à l'autre de Premiere et de Resolve. Aux extrémités
ça **s'arrête** — boucler ferait repartir un tour en arrière sous une touche
maintenue, et l'ordre est la seule chose qu'un set de caméras possède.

⚠️ **Aucun n'a de touche par défaut, et c'est le point important.** C'étaient
les quatre flèches, ce qui se lit bien sur le papier — une flèche saute au
point de montage suivant, comme partout. Ici c'est faux : ce qu'on passe la
session à faire, c'est **voler en caméra libre** pour placer un plan, et la
caméra libre d'AC se déplace aux flèches. Chaque appui destiné à bouger la vue
déplaçait aussi la sélection et emmenait le replay avec elle. Trouvé par Théo
en posant sa deuxième caméra.

Aucune touche libre évidente pour les remplacer — la caméra libre a les
flèches, WASD et la souris —, donc ils sont déclarés, listés dans le panneau
`?`, et c'est à qui en veut de choisir. **Les noms ont changé en même temps que
les défauts** : `ac.ControlButton` retient une affectation sous son nom, donc
retirer le défaut ne fait rien pour qui a déjà l'ancienne enregistrée — c'est-
à-dire exactement la personne qui a signalé le problème. Un nom neuf est une
entrée neuve, sans touche.

⚠️ **Les quatre variantes Maj ont été supprimées.** Elles parcouraient sans
déplacer le replay : la moitié clavier du Maj+clic du ruban. Le clic ne
déplace plus rien, elles n'avaient donc plus de quoi s'abstenir. Qui les avait
affectées garde quatre entrées mortes dans `controls.ini` — sans effet, et
moins coûteux que de traîner un raccourci qui fait ce que fait la touche
seule.

**Par `ac.ControlButton`, jamais par un hook clavier.** Le mécanisme de
CamTool 2 est vérifiable dans son code : `classes/hotkey.py` appelle
`keyboard.add_hotkey`, et la bibliothèque `keyboard/` vendorisée installe un
**hook bas niveau global** (`WH_KEYBOARD_LL`). Toutes les touches de la machine
y passent avant d'arriver à leur destinataire, et le callback tourne dans le
Python 3.3 embarqué d'AC — occupé à chaque frame par `acUpdate`. C'est dans le
chemin de **toutes** les touches, y compris pour qui n'utilise pas l'app.

`ac.ControlButton` n'a rien dans ce chemin : AC lit ses entrées comme
d'habitude et nous dit qu'une affectation qu'il connaît déjà s'est déclenchée.
Notre coût est une poignée de comparaisons **dans notre frame**, pas dans celle
du clavier.

C'est bien l'issue **#34**, et sa cause est confirmée par l'auteur lui-même
dans le fil. Le registre de `docs/legacy.md` la documente maintenant, avec le
second problème que le fil mélange au premier. Les touches sont des **défauts** : elles vivent dans
`controls.ini` et se réaffectent depuis le panneau `?`, section SHORTCUTS,
avec le widget de CSP.

⚠️ **Le piège, traité en un seul endroit** : quand un champ a le clavier,
Espace écrit un espace et les flèches déplacent le curseur. `shortcuts.pressed`
vérifie `wantCaptureKeyboard` une fois pour tous les raccourcis, présents et à
venir — CamTool 2 gérait ça avec ses propres drapeaux et se trompait par
endroits.

**L'indicateur ▶ / ⏸** partage la ligne de l'en-tête, sans l'agrandir. Il
**lit** et ne commande pas : `ac.getGameDeltaT()` rend zéro quand le sim ou le
replay est en pause, donc il est juste quelle que soit l'origine — barre d'AC,
autre app. Une hystérésis de trois frames évite qu'il clignote, parce qu'une
icône qui clignote est le même mensonge dit plus vite.

**Pas de bouton lecture/pause**, et c'est écrit dans le tableau DLL de
`docs/legacy.md` : aucune API CSP ne met un replay en pause. Le seul
contournement — CamTool pilotant le curseur en permanence — changerait le
comportement du replay pour tout le monde. Écarté par Théo.

## 🚫 Plus d'infobulles

Tranché par Théo devant le jeu, et la raison se généralise : **une bulle
s'affiche par-dessus le panneau qu'elle explique**. Ce qu'elle recouvre, c'est
la ligne sous le curseur et ses voisines — précisément ce qu'on regarde
pendant qu'on glisse une valeur. Une aide qui cache le travail n'est pas une
aide.

Aucune phrase n'est perdue : les 32 sont écrites et les 32 atteignent l'écran,
dans la **ligne de statut**, toujours visible, qui ne coûte pas un pixel de
hauteur et porte maintenant aussi les gestes — la seconde moitié de ce que la
bulle contenait. Le délai, qui n'existait que pour empêcher les bulles de
clignoter, part avec.

Le nom de fichier et l'indicateur ▶/⏸ en avaient chacun une, et celle du nom
de fichier tombait pile sur le ruban. Un test balaie le panneau entier : il
échoue si quoi que ce soit en affiche encore une. L'écart est noté dans
`docs/ui-interactions.md`, à côté de celui sur Échap.

**Les affectations clavier ont leur propre bouton `keys`**, à côté du `?`.
Elles pendaient au bout de la légende, au motif que celui qui lit ce que fait
une touche est là où il voudra la changer — c'était l'inverse : ce sont deux
courses, et les affectations n'étaient atteignables qu'en ouvrant un mur de
texte sur les losanges. Un seul des deux panneaux s'ouvre à la fois.

## 🔎 Trois manques trouvés par l'usage

Aucun n'était visible hors jeu, et tous les trois venaient d'un geste de
CamTool 2 qu'on avait perdu sans s'en rendre compte.

**Les champs montrent la caméra vivante.** Un paramètre sans valeur affichait
`--`, y compris en caméra libre — donc on épinglait avec le losange quelque
chose qu'on ne voyait pas. C'est pourtant *le* geste sur lequel l'outil est
bâti : placer la vue, puis l'épingler. `liveValue` lit maintenant la caméra du
jeu (`ac.getCameraPosition`, `getCameraForward`, `getCameraFOV`) quand la
lecture n'a rien à dire, et le champ l'affiche **en gris** : ce n'est pas
encore la valeur de cette caméra, le losange est ce qui la fait devenir.

Roulis et distance de mise au point n'ont pas de lecture : AC donne un vecteur
et non un angle, et rien ne dit sur quoi l'objectif fait le point. Ils restent
à `--` plutôt que d'inventer un zéro.

**Créer un fichier depuis rien.** Tous les chemins d'entrée passaient par le
chargement : une session fraîche ne pouvait travailler que sur le set de
quelqu'un d'autre, et `+cam` répondait « charge un fichier d'abord » — vrai et
d'aucune aide, puisqu'il n'y avait aucun fichier à soi. **Double-cliquer le nom
sans rien de chargé crée le fichier** (`data.newDocument`), et le préfixe de la
piste est ajouté s'il manque, sans quoi le fichier n'aurait jamais été reproposé
sur ce circuit.

### Les noms de fichiers ne montrent plus que le nom

`spa_-theo.json`, c'est trois choses collées : la piste, le nom choisi, le
format. Une seule appartient à l'utilisateur. Le panneau montrait la chaîne
entière **et la donnait au champ qui renomme** — donc le préfixe et
l'extension, modifiables, dans une boîte qui demande un nom, et en effacer un
bout produit un fichier que l'app ne reproposera jamais sur cette piste.

`core/filename` sépare et recolle, en supposant que ce qui a été tapé peut être
n'importe quoi : un préfixe et une extension qu'on venait de voir, l'un des
deux en double, un slash égaré, un point final que Windows mange en silence.
Un nom qui ne reste rien une fois nettoyé est refusé plutôt qu'écrit en
`.json`.

Et **la position de parcours suit la sauvegarde**. Nommer un set, c'est ce qui
le rend vôtre ; laisser les flèches où elles étaient faisait que le fichier
qu'on venait d'écrire avait l'air de ne pas exister.

### `+cam` peut être la première chose qu'on fait

`+cam` sans fichier répondait « no file yet ». Vrai, et sans aide : nommer un
fichier est une corvée de machine, demandée au seul moment où personne n'en
veut — celui où on regarde le virage. `+cam` crée donc le set, le bandeau dit
« unsaved set », et `Save` **ouvre le champ de nom** au lieu de refuser.

**Sauvegarder sous un nom** : il n'y en avait aucun moyen. `Save` écrasait le
fichier chargé, donc un set ne pouvait jamais devenir le vôtre. **Double-clic
sur le nom de fichier** — le même geste que renommer une caméra sur le ruban,
appliqué à la chose dont il change le nom.

**Les boutons `+cam` / `-cam` sont revenus.** Le menu au clic droit reste : il
sait *où* on visait. Mais il coûte un clic pour le cas courant, et Théo a
raison qu'un clic compte dans un geste fait quarante fois. Donc : boutons pour
« ici et maintenant », menu pour « à cet endroit précis ».

## 🏷️ Le numéro sur le segment, le nom dans la ligne de statut

**Le segment porte son numéro, et rien d'autre ; le nom va dans la ligne de
statut.** Aujourd'hui l'étiquette a trois états — le nom s'il tient, sinon le
numéro s'il tient, sinon rien, sauf celui sous le curseur écrit au-dessus du
ruban — et rien à l'écran ne dit dans lequel on est. *« Ce n'est pas clair de
parfois afficher un numéro, parfois le nom »*, et c'est juste : un libellé qui
change de nature selon la place ne se lit pas, il se devine. Le numéro reste
parce que c'est lui qui rend un set **dénombrable** ; le nom a désormais un
endroit qui ne manque jamais de place.

**Un segment trop fin même pour un chiffre reste vide**, et ça ne coûte rien :
il garde sa teinte et son trait de relais, donc il se voit et se clique, et le
survoler le nomme. Ce qui part, c'est l'écriture du nom **au-dessus** du ruban
quand le segment était trop étroit — le troisième état, celui qui empiétait sur
la ligne des losanges.

**Le même nom au survol de la carte.** Réponse à la question de Théo : oui,
mais **pas écrit sur le tracé**. Un tracé est une courbe, un nom un rectangle ;
les poser l'un sur l'autre demande de faire tourner le texte ou de tirer un
trait de rappel, deux choses qui coûtent cher et se lisent mal sur un circuit
qui se replie sur lui-même comme Spa. La carte sait déjà quelle caméra est sous
le curseur — elle dessine l'anneau de survol avec —, donc le nom part dans la
**ligne de statut**, la même que celle du ruban. Un seul endroit pour la même
question, quelle que soit la surface survolée. Un test échoue si la carte
écrit quoi que ce soit sur le tracé.

## 🛑 Charger ne détruit plus en silence — issue #26

Charger un fichier remplace tout le document et vide la pile d'annulation :
aucun retour possible. Et le bouton qui le fait est celui qu'on clique pour
lire quel fichier est ouvert. Le ticket le dit mieux : *« si l'utilisateur a
commencé à créer des caméras et appuie par accident, il perd tout »*.

Donc : **s'il y a du travail non sauvé, le premier clic arme et le second
charge**, comme Reset le fait déjà. Armé, le bouton le dit lui-même
(`lose changes? <nom>`) plutôt que de le murmurer dans la ligne de statut —
c'est la leçon que Reset avait déjà coûtée. Ce qui compte comme « non sauvé »
est la profondeur de la pile d'annulation, c'est-à-dire **le même signal que
l'étoile de `Save *`** : les deux ne peuvent pas se contredire.

**Un trou trouvé en chemin, dans Reset.** L'annulation de la question testait
`next(actions) ~= nil` — or `hint` est une action, et elle est posée à chaque
frame où le pointeur est quelque part sur le ruban ou sur l'indicateur de
lecture. Une confirmation armée se désarmait donc toute seule dès que la
souris traversait le panneau — ce qu'elle fait pour revenir au bouton.
`actedOn` ignore `hint`, et un test tombe si la règle revient en arrière.

**Ce que ça ne fait pas** : les flèches `<` `>` ne chargent rien, elles
déplacent seulement la position de parcours — rien à confirmer de ce côté.

## 🔍 #16 — deux causes mesurées et corrigées, **et le symptôme reste**

⚠️ **Ne pas marquer #16 résolu.** Théo a testé après les deux corrections
ci-dessous : *« parfois je n'ai pas de glissement, parfois oui, c'est difficile
à dire ce qui le cause »*. Ce qui est écrit ici est donc ce qu'on **sait**, pas
la solution.

### Ce que la caméra vise

Pas la voiture : un mélange bâti sur ses **50 dernières positions**
(`core/tracking`). C'est ce qui rend le panoramique fluide, et c'est le portage
exact de `Camera.calculate_cam_rot_to_tracking_car`. La cible vaut
`voiture + 0,1 × (voiture − moyenne)`.

Deux moments remplissent ce tampon de positions qui ne veulent plus rien dire,
et les deux étaient des défauts réels.

### 1. Après un saut de replay — corrigé, 1 à 3°

Le tampon n'était jamais vidé quand le replay bougeait. La frame d'après, les
50 positions parlent encore d'un endroit que la voiture a quitté. `50 frames`
pour s'en remettre, `49 m` d'erreur de visée à la première pour un saut de
500 m.

**Mais ce qui compte est l'angle, pas la distance** — le décalage pointe *le
long* du saut :

| Saut | Erreur angulaire |
|---|---|
| Droit vers la caméra | **0,00°** |
| 500 m de côté | 0,99° |
| Oblique | 0,81° |
| Petit saut, caméra proche | **2,61°** |

Corrigé par `playback.jumped`, déclenché sur un déplacement de la voiture de
plus de 2 % du tour en une frame — donc la barre de replay d'AC compte aussi.

### 2. À la prise de caméra — corrigé, 20 à 89°

L'historique était amorcé avec 50 copies de **l'origine du monde**, pour
reproduire ce que fait CamTool 2 au démarrage. Pendant 50 frames, le plan
arrive du milieu de la carte.

**La géométrie décide de l'ampleur, et c'est ce qui m'a trompé une fois.** Une
première mesure donnait 0,44° — caméra à 460 m de la voiture, origine presque
alignée derrière, la seule disposition qui annule l'effet. Avec la géométrie
réaliste (caméra de bord de piste à 40 m, circuit à 1,1 km de son origine) :
**20,5° sur 0,82 s**. Et `tests/test_trace_replay.lua` le disait depuis
toujours sans que personne le lise : sans le zero fill la visée était
« out by 1.56 rad » — **89°** — sur une vraie session enregistrée.

`legacyZeroFill` n'est donc plus piloté par le mode du fichier. Le reproduire
n'achète rien : ce transitoire n'existe qu'à l'instant où la caméra est prise,
et cet instant n'est dans aucun rendu — on active, *puis* on enregistre. Aucun
montage déjà fait ne change. L'interrupteur reste : `tests/trace.lua` le
demande explicitement, et le panneau de sondes peut l'allumer pour comparer.

> Le piège trouvé en corrigeant le 1 : le premier jet appelait `resetHistory`,
> qui obéit à `legacyZeroFill`. Sur un fichier legacy, corriger le saut le
> rendait donc **pire** — la visée arrivait de l'origine de la piste. D'où
> `playback.jumped`, distinct : un saut réamorce **toujours** depuis la vie.

**Golden master regénéré** : 24 lignes, toutes entre la frame 8 et la 48. Rien
au-delà du démarrage ne bouge, ce qui est la forme attendue.

### Ce qu'il reste, et comment le prendre

Le symptôme persiste et **il est intermittent**. C'est l'information la plus
utile qu'on ait : les deux mécanismes ci-dessus sont eux aussi
géométrie-dépendants, donc « parfois oui, parfois non » ne les disculpe pas
complètement — mais ils sont corrigés, donc quelque chose d'autre reste.

Pistes, dans l'ordre de sérieux :

1. **`ownShare` et le changement de mode de caméra.** Le SDK est explicite :
   « once `.ownShare` reaches 1, CSP would switch current camera mode to free
   camera ». Ce basculement peut très bien porter le lissage propre d'AC — et
   il **dépendrait de la caméra AC active avant la prise**, ce qui expliquerait
   exactement l'intermittence. Le panneau de sondes porte déjà une rampe
   d'`ownShare` étiquetée « candidate fix for issue #16 ».
2. **L'inertie de la caméra libre d'AC** une fois le mode basculé. La sonde
   d'**erreur de relecture** est faite pour ça : elle compare ce qu'on demande
   à la frame *n* et ce qu'AC rapporte à la frame *n+1*. Si AC lisse, l'écart
   est non nul et décroissant.
3. **L'amorçage de la visée tenue** (`haveAim`), qui lit
   `cam.transformOriginal.look` — donc là où la vue pointait **avant** la prise.

**Protocole pour transformer « parfois » en tableau**, à faire en jeu :

| À noter à chaque essai | Pourquoi |
|---|---|
| La caméra AC active avant d'appuyer sur `Take camera` (F1 cockpit, F3 TV, F7 libre…) | discrimine la piste 1 |
| Replay en lecture ou en pause | un transitoire lié au temps se voit à l'arrêt |
| L'erreur de relecture dans le panneau de sondes, pendant la seconde qui suit | discrimine la piste 2 |
| Où pointait la vue avant la prise | discrimine la piste 3 |
| Glissement : oui / non | la colonne qu'on cherche à expliquer |

Cinq à dix lignes de ce tableau valent mieux que n'importe quelle relecture du
code : deux fois déjà, la mesure a contredit ce que la lecture laissait croire.

## 📦 Sortir une version

**Un seul zip, les deux apps dedans.** CamTool 3 est en bêta et exige CSP ;
CamTool 2 n'exige rien et fait tout. Livrer les deux, c'est livrer le repli
avec le produit — quelqu'un qui bute sur un manque rouvre CamTool 2 dans la
même session, ses fichiers intacts (CamTool 3 n'écrit jamais chez elle, et
c'est testé). On scindera quand la 3 tiendra debout seule.

La marche à suivre :

```
git tag v3.0.0-beta.1
git push origin v3.0.0-beta.1
```

Le reste est dans `.github/workflows/release.yml` : il rejoue les tests et
**s'arrête s'ils échouent** — un pipeline qui ne sait pas refuser n'est qu'une
façon plus rapide de publier une build cassée, et le tag est justement le
moment où personne ne regarde la sortie des tests. Puis il construit le zip,
tamponne `VERSION` dans le manifeste depuis le tag, et crée une release **en
brouillon**. Tu écris les notes et tu publies.

**Ce qui part dans le zip est décidé par `.gitattributes`**, pas par une
seconde liste dans le workflow qui dériverait de la première. Sont exclus :
`tests/`, `tools/`, `docs/`, `CLAUDE.md`, `.github/`, et la maquette
`atr-new-ui.png` (2 Mo, soit les quatre cinquièmes du poids). `LICENSE` part —
obligation GPL v3, pas politesse — et `README.md` aussi, parce que c'est le
seul mode d'emploi que quelqu'un ait une fois le zip ouvert.

Le zip s'ouvre directement sur `apps/` et `content/` : **le dépôt a déjà la
forme du dossier de jeu**, donc `git archive` produit l'arborescence
d'installation sans aucune mise en forme. Pas de dossier enveloppe — c'est la
façon classique pour un mod d'avoir l'air installé et de ne rien faire.

**CamTool 2 part tel qu'il est dans le dépôt**, c'est-à-dire la 2.2.2 plus
l'enregistreur de traces (`classes/trace.py`), qui sert d'oracle au portage.
Éteint par défaut et impossible à allumer par accident : `settings.json` n'est
pas suivi par git, donc il ne part jamais dans le zip, et `load_settings`
remplace tout le dictionnaire par le contenu du fichier — un réglage existant
n'a pas le drapeau et ne l'aura pas. Éteint, le chemin chaud est celui de la
2.2.2 : `trace.begin` rend `None` et l'appelant reprend le `ctt` réel.

Ce que ça laisse : un appel de méthode par frame qui rend `None`, et un point
d'entrée `acShutdown` sous `try/except`. **Tranché par Théo**, qui a vérifié en
jeu que CamTool 2 démarre et fonctionne : on livre tel quel, et les notes de
release n'en parlent pas. Ne pas rouvrir pour exclure `trace.py` du zip — il
faudrait alors neutraliser l'import et deux appels dans `CamTool_2.py`, donc
modifier CamTool 2 pour la seule livraison, ce qui est plus risqué que ce que
ça évite.

**Le panneau de sondes ne part pas dans la livraison.** C'est de la surface
développeur : il sait piloter le replay et confisquer le volume du jeu. Il ne
peut pas devenir une app séparée — CSP laisserait deux scripts se parler par
`ac.connect`, mais tout l'intérêt d'une sonde est de lire les variables locales
de l'app **au moment où elles sont calculées** ; mettre un mur entre les deux,
c'est se mettre à déboguer le mur. Le bloc `[WINDOW_...] ID = main` est donc
retiré du manifeste à l'empaquetage : le Lua reste, plus aucune fenêtre ne
pointe dessus, et toi tu gardes tout en travaillant depuis le dépôt.

La découpe est dans **`core/manifest.lua`**, pure et testée, appelée par
`tools/strip_window.lua`. Pas un `sed` dans le YAML : une section d'INI n'a pas
de marqueur de fin, et ce genre de découpe écrite en expression régulière au
fond d'un fichier de workflow est la façon dont une release livre
silencieusement autre chose que prévu. Le piège réel — et il a son test — :
le paragraphe qui présente le panneau ATR est situé **entre** la dernière ligne
de la fenêtre des sondes et l'en-tête suivant, donc une coupe naïve l'emporte
avec elle. Le script **échoue** s'il ne trouve pas la fenêtre : une fenêtre
renommée livrerait le panneau qu'on voulait retirer, et personne ne va lire un
manifeste dans un zip.

Vérifié localement : 96 entrées, 1,0 Mo compressé, `VERSION = 3.0.0-beta.1`,
une seule fenêtre dans le manifeste livré.

**Le tag porte un `v`**, contrairement aux anciens (`2.2.0`…`2.2.2`), qui
restent tels quels. Le `v` rend le déclencheur du workflow net et la ligne de
version continue après 2.2.2.

### Intégration continue

`.github/workflows/tests.yml` tourne à chaque push et chaque PR : la suite
LuaJIT, et `vermin` sur le Python. Aucun des deux ne peut dire que l'app marche
en jeu — rien hors du jeu ne le peut. Ce qu'ils disent, c'est que ce qui se
vérifie sans lui tient toujours, et ils le disent **sur une autre machine**,
seul moyen de découvrir qu'un test ne passait que sur celle qui l'a écrit.

### L'icône

`apps/lua/CamTool3/icon.png`, 128 px, engendrée par `tools/make_icon.py`
(Pillow, sur le Python du poste). Un générateur plutôt qu'un PNG dessiné à la
main : une icône que personne ne peut rouvrir est une icône que personne ne
peut changer.

Le dessin n'est pas original, volontairement — même disque rouge, même anneau,
même caméra que CamTool 2, et un `3`. On trouve CamTool dans une liste de
trente apps à sa couleur ; l'icône d'un successeur doit être reconnue avant
d'être lue. La palette est relevée sur `CamTool_2_ON.png`, pas inventée.

⚠️ **`ICON` se déclare par fenêtre, pas dans `[ABOUT]`.** Le fichier seul ne
suffit pas : sans `ICON = icon.png` dans chaque bloc `[WINDOW_...]`, la liste
d'apps affiche l'icône générique. Ça ne figure nulle part dans le SDK — il
documente l'API Lua, pas l'empaquetage — et ça s'est trouvé en regardant les
manifestes des apps CSP déjà installées à côté (PureConfig, PurePlanner,
RSS_Settings) : les trois font pareil, et les trois livrent du **64×64**.

## ❓ À demander au designer d'ATR

`docs/ui-interactions.md` **a maintenant sa section « Le ruban »** : les deux
zones, chaque geste, et la raison de ceux qui ont été discutés. Elle a été
écrite sur les arbitrages de Théo, pas inventée — et elle le dit en tête de
section.

Reste à lui faire confirmer, puisque le document est le sien :

- que le ruban est bien **le navigateur principal** — il l'avait dit en
  conversation, c'est maintenant écrit, mais par nous ;
- que la bande numérotée a été **supprimée**, l'usage ayant tranché comme il
  l'avait proposé.

La **légende du `?` couvre tous les gestes** — c'est ce que le contrat exige
d'elle (« seul endroit où l'aide est exhaustive »), et deux tests échouent : un
si un geste existe sans y figurer, un autre si elle promet encore un geste
retiré.

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

- **La mise au point pendant le mouse look.** Alt maintenu, la mise au point
  glisse vers 300 m au rythme de la reprise en main (`InterpolateFrame.py`
  ~432) : avec une faible profondeur de champ réglée sur la voiture, la
  voiture devient floue dès qu'on appuie sur Alt. Constaté par Théo en jeu.
  **Gardé tel quel pour l'instant (fidèle à CamTool 2)**, décision de Théo.
  Pistes pour plus tard : garder la mise au point du fichier pendant le
  mouse look (le plus prévisible quand on vise pour épingler ensuite), ou
  garder l'autofocus sur la voiture quand la caméra en a un. C'est une ligne
  dans `core/playback` (le bloc « the focus goes long »), plus son test dans
  `tests/test_mouselook.lua`.

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
