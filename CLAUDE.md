# CLAUDE.md — CamTool 3 (Assetto Corsa)

## ⛔ Périmètre — règle absolue

Ce dépôt est extrait **dans le dossier d'installation d'Assetto Corsa**.

Périmètre autorisé, et rien d'autre :

| Chemin | Accès |
|---|---|
| `apps/python/CamTool_2/` | lecture + écriture (CamTool 2) |
| `apps/lua/CamTool3POC/` | lecture + écriture (POC Lua, branche `poc/lua`) |
| `content/gui/icons/CamTool_2_*.png` | lecture seule |
| `extension/internal/lua-sdk/` | lecture seule (définitions EmmyLua de l'API CSP) |

- Ne JAMAIS lire, lister, rechercher (grep/glob) ni modifier quoi que ce soit en dehors de ces chemins : ni le reste de `content/`, ni le reste d'`extension/`, ni `system/`, `cfg/`, les autres apps (Python ou Lua), les exécutables ou les DLL du jeu.
- `extension/internal/lua-sdk/` est de la **documentation d'API** : on la lit pour connaître les signatures CSP, on n'y écrit jamais.
- Toujours lancer les recherches avec un chemin explicite dans le périmètre (jamais `grep -r` depuis la racine du jeu).
- Si une information hors périmètre semble nécessaire (ex. SDK CSP dans `extension/internal/`), **s'arrêter et demander à Théo**.
- Ne jamais modifier `data/` (fichiers caméras des utilisateurs, ignorés par git) ni `settings.json` locaux, sauf demande explicite.

## Le projet

- CamTool : app de caméra cinématique pour les replays AC (keyframes le long de la piste, tracking de voiture, FOV/DOF, spline de piste). Utilisée pour faire des vidéos.
- Auteur original : kasperski95. Fork maintenu par tmeedend (Théo), GPL v3. Code écrit à l'origine par un non-développeur : peu de structure, beaucoup d'état global.
- Objectif de la version 3 : 1) refactoring pour la maintenabilité, 2) refonte UX (maquette proposée par ATR, vidéaste : `atr-new-ui.png`), 3) nouvelles fonctionnalités.
- **CamTool 3 exige Custom Shaders Patch (CSP).** On utilise les API CSP plutôt que les appels bas niveau / la DLL. Pas de mode dégradé sans CSP.

## Environnement d'exécution (contraintes dures)

- Python **embarqué par AC = Python 3.3** (vérifier `sys.version` dans le log si doute). Pas de pip, pas de dépendances externes.
  - Interdit : f-strings, annotations de variables, `typing`, `pathlib`, `enum`, `dataclasses`, `asyncio`, `math.isclose`, unpacking `*`/`**` généralisé, module `imp` (casse les tests sur Python récent).
  - L'ordre des `dict` n'est PAS garanti : toujours `sort_keys=True` à l'écriture JSON.
- Points d'entrée : `acMain(ac_version)` (une fois) et `acUpdate(dt)` (**à chaque frame**). Tout ce qui est dans `acUpdate` est chemin chaud : pas d'I/O, pas de log par frame, allocations minimales.
- Le répertoire courant est la racine d'AC : les chemins sont du type `./apps/python/CamTool_2/...` (voir `classes/constants.py`, `files/settings.py`).
- `stdlib/`, `stdlib64/` : `_ctypes.pyd` + wrapper DLL. `keyboard/` : bibliothèque tierce vendorisée → ne pas refactorer, ne pas styliser.
- Les exceptions sont avalées par `debug(e)` (log AC `Documents/Assetto Corsa/logs/py_log.txt` + console) : une erreur n'arrête pas le jeu, elle se voit dans le log.

## Carte du code actuel

- `CamTool_2.py` (~2600 lignes) : entrée, boucle `acUpdate`, classe UI géante `CamTool2`.
- `classes/Camera.py` : logique caméra (tracking, application des paramètres) — fortement couplé à `ac`/`ctt`.
- `classes/data.py` : modèle caméras/keyframes, sauvegarde/chargement.
- `classes/CubicBezierInterpolation.py` : interpolation — **déjà pur (aucun import `ac`)**, premier candidat aux tests.
- `classes/InterpolateFrame.py`, `MouseLook.py`, `Replay.py`, `CamMode.py`, `hotkey.py`, `general.py` (vec3, debug).
- `files/` : fichiers de données JSON par piste (`<track>_<layout>-<nom>.json`) et settings.
- `ui/` : widgets maison au-dessus de `ac.addButton` & co.
- `stdlib64/CamToolTool.py` : **seule** façade vers la caméra/replay (`ctt`), mélange `ac.ext_*` (CSP) et DLL.

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

### Équivalents Lua/CSP — validés en jeu par Théo (POC `apps/lua/CamTool3POC/`)

| Fonction DLL | Équivalent Lua | Validé en jeu |
|---|---|---|
| `IsAsyncKeyPressed` | `ac.isKeyDown(ac.KeyIndex.Shift/Control/Menu)` | ✅ les 3 détectées |
| `GetPosition` | `ac.grabCamera()` → `.transform.position` | ✅ orbite continue **sans stuttering** (#20) |
| `GetHeading` | `.transform.look` (vecteur, plus d'angle) | ✅ via la même orbite |
| `GetRoll` | `.transform.up` (vecteur, plus d'`asin`) | ✅ via la même orbite |
| `SetReplaySpeed` | **pas d'équivalent** : `ac.setReplayPosition(frame, playCounter)` piloté par frame | ✅ ralenti et accéléré fluides |
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
- Ne supprimer un appel DLL qu'avec un équivalent CSP **validé en jeu** (voir "Sondes de comparaison").
- Documenter chaque conversion d'axe/signe dans le code (AC : Y vertical ; mapping d'axes CSP déjà présent dans `get_position`).
- Mettre à jour ce tableau à chaque avancée.

## Architecture cible

Trois couches, dépendances vers l'intérieur uniquement :

1. **core/** — logique pure : modèle caméras/keyframes, interpolation, tracking, calculs d'angles, sérialisation JSON. **Aucun `import ac`, `acsys`, `ctypes`, `keyboard`.** Entrées/sorties = valeurs simples.
2. **adapters/** — seul endroit qui parle au jeu : `sim.py` (voitures, piste, replay), `camera.py` (lecture/écriture caméra), `input.py` (clavier/souris), `storage.py` (fichiers). Une interface par adaptateur, une implémentation AC/CSP, une implémentation fake pour les tests.
3. **ui/** — présentation, ne contient pas de logique métier ; appelle le core, affiche l'état.

Principes :
- Pas de singletons globaux instanciés à l'import (`data = Data()`, `ctt = CamToolTool()`…) : composition explicite dans `acMain`.
- Un état applicatif unique et explicite, passé aux fonctions, plutôt que des globales `gXxx`.
- Unités explicites dans les noms (`_rad`, `_deg`, `_m`, `track_pos_norm` pour la position normalisée 0..1 appelée `the_x` dans le code legacy).

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

Nature différente, donc traitement différent :

- **#2 est un choix d'encodage**, donc il disparaît de lui-même si CamTool 3
  stocke le FOV en degrés : la bizarrerie ne vit plus que dans le lecteur des
  anciens fichiers.
- **#1 et #4 sont des bugs de calcul.** Les corriger déplace les courbes, donc
  change des vidéos déjà montées. À mettre derrière le sélecteur de version.
- **#3 est un trou de validation.** Le corriger est sûr quelle que soit la
  version : l'ancien code ne produisait aucune valeur exploitable (exception
  d'un côté, `inf` de l'autre), donc aucune vidéo ne peut en dépendre.

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

## Tests

Claude ne peut pas lancer Assetto Corsa. La vérification repose sur trois niveaux :

### 1. Tests automatiques hors jeu (obligatoires)
- `pytest` sur Python récent, dossier `tests/` (exclu du package de release).
- `tests/fakes/` : faux modules `ac`, `acsys`, `keyboard`, faux `ctt` injectés via `sys.modules` → permettent d'importer et d'exécuter le code, y compris le legacy non modifié.
- Tests unitaires du core (interpolation, angles, migrations JSON).
- **Golden master / caractérisation** : avant de refactorer une zone, figer son comportement actuel (entrées rejouées → sorties caméra par frame : position, rotation, fov, dof) et vérifier après refactoring que les sorties sont identiques à epsilon près.
- Traces de jeu : en mode dev (`settings.json` → `"dev_record_trace": true`), enregistrer par frame les entrées (dt, position replay, état des voitures utilisées) et les sorties caméra dans un JSONL hors du chemin chaud (buffer + écriture différée). Quelques traces courtes sont versionnées en fixtures.
- Compatibilité 3.3 : `vermin --no-tips -t=3.3- --violations .` (hors `keyboard/` et `tests/`) doit passer.

Commande de validation avant de proposer une modification : `pytest -q && vermin --no-tips -t=3.3- --violations classes files ui core adapters CamTool_2.py`.

### 1 bis. Tests Lua hors jeu (branche `poc/lua`)

Même principe côté Lua, mêmes exigences. **Outillage : un seul binaire.**

- Runtime : **LuaJIT 2.1** (`winget install DEVCOM.LuaJIT`), parce que CSP tourne
  sur LuaJIT. `_VERSION` = **Lua 5.1** : c'est le carcan de syntaxe du Lua, le
  pendant de Python 3.3 côté Python.
- Runner : `apps/lua/CamTool3POC/tests/runner.lua`, ~70 lignes de Lua pur
  versionnées. Pas de `busted`, pas de `luarocks` (chaîne de compilation C sous
  Windows), cohérent avec un projet qui tourne sur des interpréteurs embarqués
  où rien ne s'installe.
- Les fichiers de test sont listés explicitement dans `tests/run.lua` : scanner
  un dossier demanderait `lfs`, donc une dépendance C.

Commande de validation, depuis `apps/lua/CamTool3POC/` : `luajit tests/run.lua`
(code de sortie non nul si un test échoue).

Piège de portage déjà identifié et couvert par un test : **Lua ne lève pas sur
une division par zéro**, il renvoie `inf`. Là où Python lève une exception
avalée par `debug(e)` (l'appelant garde sa valeur précédente), le Lua propage un
`inf` jusqu'à la caméra. Tout ce qui lit une saisie utilisateur ou un fichier
doit rejeter ces cas en amont.

### 2. Sondes de comparaison (en jeu, pour la DLL)
Petit module de debug activable qui logge côte à côte, pendant quelques secondes, la valeur DLL et la valeur CSP candidate (heading, roll, position…) pour déduire mapping d'axes, signe et décalage de frame.

### 3. Checklist de test en jeu
Toute modification touchant `adapters/`, l'UI ou `acUpdate` se termine par une **checklist courte et concrète** pour Théo (quoi lancer, quoi cliquer, quoi observer, quoi chercher dans `py_log.txt`). Ne jamais affirmer que "ça marche en jeu".

## Méthode de travail

- **Refactoring et changement de comportement ne sont jamais mélangés** dans un même commit.
- Petits pas : un commit = une transformation, tests verts à chaque étape.
- Avant toute tâche non triviale : proposer un plan et attendre validation.
- Ne pas "corriger au passage" un comportement bizarre du legacy : le signaler, il est peut-être voulu (ou utilisé par les vidéastes).
- Supprimer le code commenté mort seulement quand l'équivalent est validé (le code commenté documente souvent les tentatives CSP échouées — reporter l'info dans le tableau DLL avant suppression).
- Code, identifiants, commentaires et messages de commit en anglais. Échanges avec Théo en français.
- Branche `camtool-3` pour la refonte ; les correctifs 2.x restent possibles sur `main`.

## Refonte UX — règles actées

- **Cible : le panneau du haut de `atr-new-ui.png`** ("CAMTOOL 2.5", 3 colonnes colorées). Les captures du bas sont l'UI actuelle à onglets (Camera → violet, Transform → vert, Tracking → orange).
- **Vue unique, pas d'onglets** : tous les paramètres d'une caméra visibles en même temps (ATR perd du temps à changer d'onglet).
- **ISO fonctionnel** : la nouvelle UI couvre 100 % de `docs/ui-inventory.md`. Tout élément absent de la maquette est un **oubli** et doit être réintégré. Aucun bouton, raccourci ou comportement supprimé sans accord explicite de Théo.
- **Saisie rapide souhaitée** : glisser la souris sur une valeur et saisie clavier directe, en plus des flèches. Attention : le clic sur la valeur est déjà le *toggle de keyframe* (voir inventaire) → choisir un autre geste et rendre visible l'état keyframé/non keyframé de chaque paramètre. Proposer le geste à Théo avant d'implémenter.
- Conserver les modificateurs Ctrl (pas ÷ 4) et Shift (pas × 4).

## Problèmes connus et pistes (issues GitHub)

Hypothèses issues de la lecture du code, **à confirmer par un test** avant toute correction :

- **#38 artefacts à petit FOV** : l'ancien `set_fov` ajustait le near clipping (`near = clamp(2 - fov/50, 0.1, 2)`, lignes commentées dans `CamToolTool.set_fov`) ; la version CSP ne le fait plus → z-fighting probable.
- **#37 interpolation** : chaque paramètre est interpolé indépendamment. Position/rotation : Bézier cubique par canal (`interpolate`) avec corrections spéciales sur le premier et le dernier segment ; FOV, shake, offsets/forces de tracking : easing sinus (`interpolate_sin`) qui marque un arrêt à chaque keyframe ; splines enregistrées : linéaire (`interpolate_spline`). Rotations en angles d'Euler séparés, sans normalisation ±π visible dans l'interpolation des keyframes (contrairement au tracking dans `Camera.py`).
- Voir aussi le **registre des bizarreries du legacy** dans « Compatibilité des
  données » : quatre comportements confirmés, chacun reproduit et épinglé par un
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
- **#23 dernière caméra buguée** : à reproduire en test. Voir le wraparound de
  `get_prev_camera` et le décalage `the_x -= 1` de `is_last_camera()`.
- Pas d'**annuler/refaire** : prévoir une pile de snapshots de l'état caméras (données petites, JSON) alimentée par un point d'entrée unique de modification.
- Toute nouvelle méthode d'interpolation doit être **optionnelle** (mode legacy par défaut) pour ne pas modifier les vidéos existantes.
- Visualiser les courbes d'interpolation hors jeu (matplotlib dans `tools/`) pour déboguer sans lancer AC.

## ✅ Décision actée : CamTool 3 sera une app Lua CSP

Tranché par Théo après le POC (`apps/lua/CamTool3POC/`, branche `poc/lua`).
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

Reste à faire, par ordre d'importance :

1. **Fidélité du tracking** — le legacy moyenne plusieurs frames de position et
   extrapole d'un pas pour anticiper ; le POC vise la position courante, d'où un
   retard dans les virages rapides.
2. **Splines enregistrées** (pas implémentées), shake, focus point DOF, smart
   tracking.
3. **L'UI** (maquette ATR) — le gros du travail, sans risque technique connu.
4. L'écriture de fichiers (volontairement hors périmètre du POC).

## Décisions ouvertes (ne pas trancher seul)

- Déplacement éventuel du dépôt hors du dossier du jeu (jonction Windows vers `apps/python/CamTool_2`).
- **Où poursuivre le développement** : `poc/lua` est une branche de POC. La
  suite doit-elle repartir sur `camtool-3` (la branche prévue pour la refonte),
  et que garde-t-on du POC — les sondes de capacités sont-elles encore utiles
  une fois la décision prise ?
- `interpolation_mode` est **par fichier** ; le passer par caméra permettrait de
  mélanger anciennes et nouvelles caméras dans un même set.
- Le **bug `SolveCubic`** (registre des bizarreries) : corriger dans le mode
  `fixed`, ou le garder tel quel ?
