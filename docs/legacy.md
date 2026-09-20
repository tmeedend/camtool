# CamTool 2 — savoir accumulé

> Tout ce qui a été **établi** sur le code et les données existants : en
> exécutant le vrai code Python, en lisant le SDK CSP, ou en testant en jeu.
> Stable une fois écrit — à compléter, rarement à corriger.
>
> L'avancement est dans `docs/etat.md`, les règles dans `CLAUDE.md`.

**Ne rien écrire ici qui n'ait été vérifié.** Ce document sert à ne pas refaire
deux fois la même enquête : une hypothèse non vérifiée qui s'y glisse coûte plus
cher qu'une absence.

## DLL sans code source (`CamTool_1-16.dll`)

Code source indisponible, liée à une version précise d'AC. Objectif : **zéro appel DLL dans CamTool 3**.
Appels encore utilisés dans `CamToolTool.py` :

| Fonction DLL | Usage | Piste de remplacement CSP | Statut |
|---|---|---|---|
| `IsAsyncKeyPressed` | Alt/Shift/Ctrl pour mouse look | `ac.ext_isButtonPressed` (commenté "keys not working") | à investiguer |
| `GetPosition` (`get_position_old`) | évite le stuttering, issue #20 | `ac.ext_getCameraPositionAxis` (timing de frame ?) | à investiguer |
| `GetHeading` | cap caméra | `ac.ext_getCameraYawRad` / `ext_getCameraDirection` (convention de signe/axe ?) | à investiguer |
| `GetRoll` | roulis (via asin) | `ac.ext_getCameraRollRad` (commenté "not working") | à investiguer |
| `SetReplaySpeed` | vitesse replay | à trouver | à investiguer |
| `GetVolume` / `SetVolume` | fondu audio au changement de caméra | `ac.ext_*AudioVolume` cause des bugs son | à investiguer |

Les statuts ci-dessus restent « à investiguer » : ils concernent le remplacement
**en Python**, dans `CamToolTool.py`, et personne n'a testé ces `ac.ext_*`.

### Équivalents Lua/CSP — validés en jeu par Théo (POC `apps/lua/CamTool3/`)

| Fonction DLL | Équivalent Lua | Validé en jeu |
|---|---|---|
| `IsAsyncKeyPressed` | `ac.isKeyDown(ac.KeyIndex.Shift/Control/Menu)` | ✅ les 3 détectées |
| `GetPosition` | `ac.grabCamera()` → `.transform.position` | ✅ orbite continue **sans stuttering** (#20) |
| `GetHeading` | `.transform.look` (vecteur, plus d'angle) | ✅ via la même orbite |
| `GetRoll` | `.transform.up` (vecteur, plus d'`asin`) | ✅ via la même orbite |
| `SetReplaySpeed` | **pas d'équivalent** : `ac.setReplayPosition(frame, playCounter)` piloté par frame | ✅ ralenti et accéléré fluides |

⚠️ **Et toujours pas d'équivalent pour la PAUSE.** Vérifié en balayant les
quatre-vingts `ac.set*` du SDK : rien ne met un replay en pause.
`ui.setKeyboardButtonDown` ne dépanne pas non plus — « affects current IMGUI
context only », elle ne parle pas au jeu. Le seul contournement serait le même
que ci-dessus, CamTool pilotant le curseur en permanence, ce qui changerait le
comportement du replay pour tout le monde — **écarté par Théo**.

En revanche **lire** l'état est documenté et fiable : `ac.getGameDeltaT()`
rend zéro « if sim **or replay** are paused », donc quelle que soit l'origine
de la pause. D'où un indicateur, et pas un bouton.
| `GetVolume` / `SetVolume` | `ac.getAudioVolume` / `ac.setAudioVolume` | ✅ rampes sans artefact sonore |

Également validé en jeu : `.fov` (degrés, direct), `.dofFactor`/`.dofDistance`,
et `.ownShare` (fondu natif AC ↔ script, transition douce → piste sérieuse pour **#16**).

**#38 non reproduit** : aucun artefact observé en descendant le FOV jusqu'à 2°.
Cela ne veut pas dire que c'est réglé — il faut d'abord un cas qui reproduit le
bug dans la version Python pour comparer à scène égale.

**Lire la caméra vivante d'AC** (pour créer un keyframe depuis la vue courante) :
résolu. `transformOriginal` se fige à `ownShare = 1` parce qu'AC lâche la caméra,
mais `ac.getCameraPosition/Forward/Up/FOV` continuent de reporter la caméra
vivante tant qu'on ne la tient pas. ✅ Validé en jeu, y compris l'aller-retour
complet : capture de la vue courante → grab → restitution exacte de la pose.
**C'est le cycle « je place la vue → je keyframe → je rejoue » : la brique
centrale de CamTool est prouvée en Lua.**

**Mouse look** : ✅ fonctionne (`uiState.mouseDelta`, gaté par une touche
modificatrice comme dans CamTool 2). Réserve d'ergonomie : la visée est moins
douce que la caméra libre d'AC (F7), qui applique visiblement un lissage. Le POC
envoie le delta souris brut — à corriger par un lissage exponentiel, ce n'est pas
une limite de l'API.

Règles :
- Ne jamais ajouter de nouvel appel DLL.
- Ne supprimer un appel DLL qu'avec un équivalent CSP **validé en jeu** (voir « Sondes de comparaison » dans `CLAUDE.md`).
- Documenter chaque conversion d'axe/signe dans le code (AC : Y vertical ; mapping d'axes CSP déjà présent dans `get_position`).
- Mettre à jour ce tableau à chaque avancée.

## Compatibilité des données

- Les fichiers JSON existants des utilisateurs (`data/*.json`) doivent rester chargeables. Exemples de référence : `data/spa_-init.json`, `data/ks_red_bull_ring_layout_gp-init.json` (à copier en fixtures de test).
- Introduire un champ `version` de schéma + fonctions de migration pures et testées. Jamais de rupture silencieuse.
### Registre des bizarreries du legacy

Quatre comportements confirmés **en exécutant le vrai code Python**, pas déduits
par lecture. Tous reproduits à l'identique dans le portage Lua et épinglés par
un test, pour qu'aucune correction n'arrive par accident.

| # | Comportement | Déclencheur | Effet observable | Test |
|---|---|---|---|---|
| 1 | `SolveCubic` écrit `return result` au lieu de `self.result` → `NameError` | racine double exacte, racine simple dans [0,1] | `GetY` avale → `None` → `interpolate` avale son `TypeError` → **paramètre caméra `None` pour la frame** | `test_cubic.lua` |
| 2 | `convert_fov_2_focal_length` renvoie la sentinelle `0.00001` **dans les deux sens** | `val == 0` | `encode` et `decode` ne sont pas inverses : `decode(encode(0))` = 99985 | `test_fov.lua` |
| 3 | `1/(val+15)` non gardé | FOV exactement −15 | division par zéro. Python lève (comportement exact du gestionnaire appelant **non vérifié**) ; Lua renvoie `inf` qui se propage | `test_fov.lua` |
| 4 | `SolveQuadratic(0, 0, c)` renvoie `c` | cubique dégénérée, tous coefficients nuls sauf `d` | la constante est servie comme paramètre de courbe `t`, sans borne [0,1] | `cubic_golden.lua` |
| 5 | Mélange de position : les axes Y et Z utilisent `ctt.get_position(0)` — l'axe **X** (`InterpolateFrame.py` ~156 et ~177) | `transform_loc_strength < 1` | Y et Z sont mélangés avec la coordonnée X de la caméra. Copier-coller. **Dormant** : vaut 1.0 sur les 566 caméras de référence, jamais keyframé | — |
| 6 | `locCameraData.transform_rot_strength = loc_transform_loc_strength` (~119) | `transform_loc_strength` keyframé | la force de **translation** est écrite dans le cache de la force de **rotation**. **Dormant** : jamais keyframé dans les fichiers de référence | — |
| 7 | `self.__shake_offset / info.graphics.replayTimeMultiplier` (`Camera.py` ~644) — division **sans affectation**, le résultat est jeté | shake d'offset actif en ralenti ou accéléré | le shake d'offset n'est **pas** mis à l'échelle par la vitesse de replay, contrairement au shake de rotation qui l'est. Diviser maintenant changerait le rendu des caméras existantes | `test_shake.lua` |

Nature différente, donc traitement différent :

- **#2 est un choix d'encodage**, donc il disparaît de lui-même si CamTool 3
  stocke le FOV en degrés : la bizarrerie ne vit plus que dans le lecteur des
  anciens fichiers.
- **#1 et #4 sont des bugs de calcul.** Les corriger déplace les courbes, donc
  change des vidéos déjà montées. À mettre derrière le sélecteur de version.
- **#3 est un trou de validation.** Le corriger est sûr quelle que soit la
  version : l'ancien code ne produisait aucune valeur exploitable (exception
  d'un côté, `inf` de l'autre), donc aucune vidéo ne peut en dépendre.

### Les caméras d'Assetto Corsa : un cycle de six, pas de cinq

`CamMode.changeCamModeZero` (`classes/CamMode.py`) calcule
`numberOfF1 = 6 - last_cam_offset + offset` puis retranche 6 s'il dépasse :
**le cycle de la famille F1 a six positions** dans le modèle de CamTool 2, de
0 à 5.

| offset | nom CamTool 2 | `ac.DrivableCamera` de CSP |
|---|---|---|
| 0 | chase | `Chase` = 0 |
| 1 | chase far | `Chase2` = 1 |
| 2 | hood | `Bonnet` = 2 |
| 3 | subjective | `Bumper` = 3 |
| 4 | cockpit | `Dash` = 4 |
| 5 | **steering wheel** | **rien — l'énumération s'arrête à 4** |

Les cinq premières correspondent une à une. La sixième n'a **pas de nom** côté
CSP, et la question s'est posée de savoir si elle existait : la demander
aurait pu retomber sur la cinquième, rendant `steering wheel` et `cockpit`
identiques à l'écran.

**Vérifié en jeu par Théo : ce sont bien deux vues différentes.** La sixième
position existe donc, `ac.setCurrentDrivableCamera(5)` l'atteint, et
**l'énumération `ac.DrivableCamera` du SDK est incomplète** — à retenir avant
de se fier à ses bornes pour autre chose.

`CamTool3.lua` garde la relecture de `sim.driveableCameraMode` à la frame
suivante, qui logge `WARNING ... settled on N` si le jeu retient autre chose
que ce qu'on a demandé. Elle ne se déclenche plus ici ; elle reste parce
qu'une autre version de CSP pourrait ne pas se comporter pareil, et qu'une
caméra silencieusement remplacée est invisible autrement.

### Migration à sens unique — acté par Théo

**CamTool 3 lit les fichiers CamTool 2 et écrit toujours le nouveau format.**
Les nouveaux fichiers ne doivent pas porter les erreurs du registre ci-dessus.

**Deux axes distincts, ne jamais les fusionner :**

| Champ | Sens |
|---|---|
| `version` | comment les valeurs sont **encodées** sur disque |
| `interpolation_mode` | quels **calculs** de courbe s'appliquent (`legacy` / `fixed`) |

Les confondre est l'erreur facile : migrer un fichier vers le nouvel encodage ne
doit **pas** le basculer vers les courbes corrigées, sinon des vidéos déjà
montées changeraient. Un fichier migré est donc `version = 1` **et**
`interpolation_mode = 'legacy'`. Seules les caméras créées dans CamTool 3
obtiennent `'fixed'`, et le mode est conservé à la sauvegarde.

Implémenté dans `core/data.lua`, qui prend une table déjà parsée (le parsing
JSON reste à l'adaptateur, côté CSP) — c'est ce qui rend la migration testable
hors jeu.

État de la validation : les **32** fichiers de référence passent le chargeur Lua,
566 caméras, 1768 valeurs de FOV, toutes décodées entre 0,5° et 55,4°, aucune
nulle ni négative. `camera_fov` est le seul champ encodé ;
`camera_focus_point` contient des mètres bruts.

Reste ouvert : `interpolation_mode` est **par fichier**. Le mettre par caméra
permettrait de mélanger anciennes et nouvelles caméras dans un même set, au prix
de plus de complexité. À trancher si le besoin apparaît.

- La compatibilité porte sur la **sémantique**, pas seulement la syntaxe JSON : `camera_fov` est stocké sous forme convertie `1/(fov+15)` (voir `convert_fov_2_focal_length`), les angles sont en radians, `camera_in`/`the_x` sont des positions normalisées 0..1, deux modes `pos` et `time`. Toute nouvelle implémentation doit reproduire ces conventions à l'identique (vérifié par golden master).

## Problèmes connus et pistes (issues GitHub)

Hypothèses issues de la lecture du code, **à confirmer par un test** avant toute correction :

- **#38 artefacts à petit FOV** : l'ancien `set_fov` ajustait le near clipping (`near = clamp(2 - fov/50, 0.1, 2)`, lignes commentées dans `CamToolTool.set_fov`) ; la version CSP ne le fait plus → z-fighting probable.
- **#37 interpolation** : chaque paramètre est interpolé indépendamment. Position/rotation : Bézier cubique par canal (`interpolate`) avec corrections spéciales sur le premier et le dernier segment ; FOV, shake, offsets/forces de tracking : easing sinus (`interpolate_sin`) qui marque un arrêt à chaque keyframe ; splines enregistrées : linéaire (`interpolate_spline`). Rotations en angles d'Euler séparés, sans normalisation ±π visible dans l'interpolation des keyframes (contrairement au tracking dans `Camera.py`).
- Voir aussi le **registre des bizarreries** plus haut dans ce fichier : six comportements confirmés, chacun reproduit et épinglé par un
  test dans le portage Lua.
- **Le cap n'est PAS `rot_z`.** Erreur coûteuse, à ne pas refaire. Le cap final
  est un mélange pondéré de trois sources (`InterpolateFrame.py` ~283), chacune
  ramenée à la révolution la plus proche par `normalize_angle` avant le blend :
  1. `rot_z` keyframé, pondéré par `transform_rot_strength`, mélangé au cap courant
  2. la spline enregistrée
  3. **la direction vers la voiture suivie**, pondérée par `tracking_strength_heading`
  **98 % des 566 caméras de référence utilisent le tracking** (8 seulement visent
  sans lui) : pour presque toutes, c'est la source 3 qui donne la visée. Toute
  lecture de caméra qui n'applique que `rot_z` pointera n'importe où.
- **Convention d'angles, explicite dans `Camera.calculate_cam_rot_to_tracking_car`** —
  inutile de la deviner :
  `heading = atan2(dx, dy) + pi/2` et `pitch = atan2(dz, sqrt(dx²+dy²))`,
  deltas en espace CamTool (Z-up). Portée dans `core/angles.lua`, avec un test
  d'aller-retour qui vérifie que `lookVector` inverse exactement `aimAt`.
- **Axes** : CamTool stocke en **Z-up**, AC est en **Y-up**. `position AC =
  vec3(loc_x, loc_z, loc_y)`. Confirmé deux fois : les splines de piste mettent
  tout le dénivelé dans `loc_z` (Spa 102 m, Red Bull Ring 63 m), et
  `CamToolTool.get_position` mappe l'axe CamTool 2 vers l'axe CSP 1.
- **Interpolateur non réentrant** : le singleton `interpolation` stocke ses variables de travail dans `self` (`self.i`, `self.points`, `self.ratio`…) → fuite d'état possible entre appels. À corriger en premier lors du refactoring (variables locales, fonctions pures).
- **#16 glissement à l'activation — CAUSE CONFIRMÉE en jeu par Théo.** `Camera.py`
  initialise son historique de positions de voiture avec **50 vecteurs nuls**
  (`__max_tracked_car_positions = 50`, remplis de `vec3()` = origine). Pendant
  les 50 premières frames de tracking, la moyenne est donc tirée vers l'origine
  du monde et la position extrapolée (`latest + (latest - avg)`) déborde dans
  la direction opposée. Le portage Lua amorce l'historique avec le premier
  échantillon réel. Théo a comparé les deux en jeu avec la case à cocher du POC :
  **le glissement apparaît avec le remplissage à zéro et disparaît sans.**
  Reste à confirmer que c'est bien le même glissement que celui rapporté dans
  l'issue sur CamTool 2 (le POC reproduit le legacy, il ne l'exécute pas).
- **#25 shake non keyframable — élément concret.** `camera_shake_strength` est
  bien interpolé (easing sinus), mais `camera_offset_shake_strength` a un
  emplacement dans chaque keyframe et est pourtant lu **au niveau caméra**,
  jamais interpolé. Idem pour `spline_affect_pitch`/`roll`/`heading`.
- **#23 dernière caméra buguée — CAUSE CONFIRMÉE en jeu par Théo.**
  La dernière caméra est active de son `camera_in` jusqu'à la fin du tour, puis
  au-delà de la ligne jusqu'à ce que la première prenne le relais. Pour
  interpoler à travers ce saut, CamTool lit ses keyframes **un tour en arrière**
  (`the_x -= 1`), ce qui suppose qu'ils soient stockés en négatif.
  Deux des trois dernières caméras multi-keyframes des fichiers de référence le
  sont (Red Bull Ring `[-0.096 … 0.08]`, Spa `[-0.102 … 0.062]` avec un
  `camera_in` de **1.0078**). **La troisième non** : le_lancone a ses keyframes
  à `[0.947, 0.962, 0.964]`, entièrement avant la ligne.
  Or le legacy décale quand même — il ne teste que « est-ce la dernière » et
  « `the_x > 0.5` ». La requête tombe donc à −0,05, avant tous les keyframes, et
  `interpolate` renvoie le premier : **la caméra se fige dessus tout du long.**
  Correctif en mode `fixed` : ne décaler que si les keyframes sont réellement
  stockés décalés (`evaluate.hasWrappedKeyframes`). Les deux comportements sont
  derrière une case à cocher, legacy par défaut.
  **Confirmé dans CamTool 2** : sur `le_lancone` (fichier `lancia`), la dernière
  caméra doit passer de 54,2° à 12,3° de FOV à 96,36 % du parcours. Le zoom ne
  se produit pas — elle reste figée sur son premier keyframe, exactement comme
  le prédit le mécanisme ci-dessus. Le même fichier dans CamTool 3 reproduit le
  bug case cochée et zoome correctement case décochée.
  Note : le déclencheur ne teste pas s'il s'agit d'un circuit, donc le bug frappe
  aussi les spéciales de rallye, où le décalage n'a même pas de raison d'être.
  **Contre-épreuve passée** : sur `ks_red_bull_ring_layout_gp-init.json`, dont la
  dernière caméra (UI n°11) traverse la ligne avec 6 keyframes stockés décalés,
  la séquence de FOV (1,00° → 3,32° → 2,50° → 4,50°) est **identique** case
  cochée ou décochée. La détection `hasWrappedKeyframes` reconnaît donc bien le
  cas correct sans le modifier. Les trois niveaux sont validés : bug reproduit
  dans CamTool 2, reproduit puis corrigé dans CamTool 3, cas sain intact.
  **Reste à trancher : le correctif doit-il devenir le comportement par défaut ?**
  (voir « Décisions ouvertes » dans `docs/etat.md`)

  Deux anomalies de données trouvées au passage, sans rapport avec le code :
  `spa_-ATR.json` a une dernière caméra à **un seul keyframe** (le décalage n'a
  alors aucun effet observable), et `spa_-init.json` a une dernière caméra avec
  `camera_in = 1.0078` — **jamais activée**, puisque la sélection compare
  `position < camera_in` et que la position ne dépasse pas 1.
- Pas d'**annuler/refaire** : prévoir une pile de snapshots de l'état caméras (données petites, JSON) alimentée par un point d'entrée unique de modification.
- Toute nouvelle méthode d'interpolation doit être **optionnelle** (mode legacy par défaut) pour ne pas modifier les vidéos existantes.
- Visualiser les courbes d'interpolation hors jeu (matplotlib dans `tools/`) pour déboguer sans lancer AC.
