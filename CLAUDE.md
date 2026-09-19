# CLAUDE.md — CamTool 3 (Assetto Corsa)

## 📍 Où trouver quoi

Ce fichier est chargé dans **chaque** session : il ne garde que les règles, les
contraintes et la carte du code — ce qui ne bouge pas. Le reste vit à côté.

| Fichier | Contenu | Quand le lire |
|---|---|---|
| **`docs/etat.md`** | Où on en est : ce qui est porté, les chantiers restants, les décisions ouvertes, l'état des branches | **En premier**, à chaque reprise |
| `docs/legacy.md` | Savoir accumulé sur CamTool 2 : tableau DLL et équivalents Lua, registre des bizarreries, conventions d'axes et d'angles, sémantique des données, causes des issues | Avant de toucher au portage |
| `docs/ui-inventory.md` | Inventaire exhaustif de l'UI CamTool 2 | Avant la refonte UX |

**Règle de rangement : l'état va dans `docs/etat.md`, pas ici.** Une information
qui périme à chaque commit n'a rien à faire dans un fichier chargé partout.
Inversement, une règle ou une contrainte dure reste ici.

## ⛔ Périmètre — règle absolue

Ce dépôt est extrait **dans le dossier d'installation d'Assetto Corsa**.

Périmètre autorisé, et rien d'autre :

| Chemin | Accès |
|---|---|
| `apps/python/CamTool_2/` | lecture + écriture (CamTool 2) |
| `apps/lua/CamTool3/` | lecture + écriture (CamTool 3, branche `camtool-3`) |
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

## Architecture cible

Trois couches, dépendances vers l'intérieur uniquement :

1. **core/** — logique pure : modèle caméras/keyframes, interpolation, tracking, calculs d'angles, sérialisation JSON. **Aucun `import ac`, `acsys`, `ctypes`, `keyboard`.** Entrées/sorties = valeurs simples.
2. **adapters/** — seul endroit qui parle au jeu : `sim.py` (voitures, piste, replay), `camera.py` (lecture/écriture caméra), `input.py` (clavier/souris), `storage.py` (fichiers). Une interface par adaptateur, une implémentation AC/CSP, une implémentation fake pour les tests.
3. **ui/** — présentation, ne contient pas de logique métier ; appelle le core, affiche l'état.

Principes :
- Pas de singletons globaux instanciés à l'import (`data = Data()`, `ctt = CamToolTool()`…) : composition explicite dans `acMain`.
- Un état applicatif unique et explicite, passé aux fonctions, plutôt que des globales `gXxx`.
- Unités explicites dans les noms (`_rad`, `_deg`, `_m`, `track_pos_norm` pour la position normalisée 0..1 appelée `the_x` dans le code legacy).

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

`vermin` tourne sur le Python **du poste**, jamais dans AC : c'est un analyseur
statique, `-t=3.3-` est la cible qu'il vise, pas l'interpréteur qui l'exécute.
Comme `luajit`, il n'est pas dans le `PATH` des sessions d'outillage, et
`python -m vermin` ne marche pas (paquet sans `__main__`) — utiliser
`%APPDATA%\Python\Python312\Scripts\vermin.exe`. Les dossiers `core/` et
`adapters/` de la commande n'existent pas encore côté Python : aujourd'hui elle
se réduit à `classes files ui CamTool_2.py`.

### 1 bis. Tests Lua hors jeu (branche `camtool-3`)

Même principe côté Lua, mêmes exigences. **Outillage : un seul binaire.**

- Runtime : **LuaJIT 2.1** (`winget install DEVCOM.LuaJIT`), parce que CSP tourne
  sur LuaJIT. `_VERSION` = **Lua 5.1** : c'est le carcan de syntaxe du Lua, le
  pendant de Python 3.3 côté Python.
- Runner : `apps/lua/CamTool3/tests/runner.lua`, ~70 lignes de Lua pur
  versionnées. Pas de `busted`, pas de `luarocks` (chaîne de compilation C sous
  Windows), cohérent avec un projet qui tourne sur des interpréteurs embarqués
  où rien ne s'installe.
- Les fichiers de test sont listés explicitement dans `tests/run.lua` : scanner
  un dossier demanderait `lfs`, donc une dépendance C.

Commande de validation, depuis `apps/lua/CamTool3/` : `luajit tests/run.lua`
(code de sortie non nul si un test échoue). **`luajit` n'est pas dans le `PATH`
des sessions non interactives** : depuis un outil, utiliser le chemin complet
`%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`.

Ce que la suite couvre, au-delà des tests unitaires :

- `tests/lap.lua` déroule **un tour entier** hors jeu, soit à travers l'app et
  les faux CSP, soit directement dans `core/playback`. La voiture suit le tracé
  enregistré dans le fichier caméra lui-même quand il y en a un.
- `tests/fixtures/playback_golden.lua` fige les sorties caméra de quatre
  scénarios : **golden master, à regénérer seulement pour un changement de
  comportement voulu** (`luajit tools/gen_playback_golden.lua`, et le dire dans
  le message de commit).
- `tests/sweep.lua` cherche dans un tour ce qu'on cherchait à l'œil en jeu :
  `inf`/`nan`, vecteur look non unitaire, FOV absurde, caméra qui se téléporte
  au milieu de son plan, caméra inatteignable.
- `tests/trace.lua` rejoue une **trace CamTool 2** (enregistrée en jeu par
  `apps/python/CamTool_2/classes/trace.py`, convertie par
  `tools/trace_to_lua.py`) dans `core/playback` et mesure l'écart. C'est le
  seul oracle : les autres couches comparent le portage à lui-même.

Pièges déjà identifiés et couverts par un test :

- **Lua ne lève pas sur une division par zéro**, il renvoie `inf`. Là où Python
  lève une exception avalée par `debug(e)` (l'appelant garde sa valeur
  précédente), le Lua propage un `inf` jusqu'à la caméra. Tout ce qui lit une
  saisie utilisateur ou un fichier doit rejeter ces cas en amont.

- **Un libellé de widget qui change doit utiliser `###`, jamais `##`.** ImGui
  hache **tout le libellé** pour l'identité d'un widget ; seul `###` fait de ce
  qui le suit l'identité à lui seul. Un bouton dont la partie visible change —
  et la partie visible d'un champ de valeur *est* la valeur — devient un autre
  widget à l'instant où elle change : ImGui lâche l'élément actif, et un
  glissé s'arrête après un seul pas. Coûte un lancement de jeu à diagnostiquer,
  une seconde à éviter. Un test balaie tout le panneau : dessiné deux fois avec
  tout identique sauf les mots, chaque widget doit garder son identité.

- **Ne pas mélanger `ui.mousePos()` et `ui.getCursor()`.** Le premier est en
  coordonnées écran (soumises à l'échelle de l'UI), le second en coordonnées
  fenêtre. Un test de collision doit être mesuré contre **la même origine que
  le dessin** qu'il vise — et, quand c'est possible, être **rendu visible**
  (voir l'anneau de survol de la carte) : un calcul qu'on ne voit pas est un
  calcul qu'on ne peut pas déboguer en jeu.

- **`type(v) == 'function'` ne teste pas si `v` est appelable.** CSP lie une
  partie de l'espace `ac` par le FFI de LuaJIT, et un pointeur de fonction C
  est un `cdata` : appelable, mais `type` dit autre chose. Tester la présence,
  et laisser `pcall` trancher.

- **Les faux ne font pas avancer le temps tout seuls.** L'app garde son travail
  à une exécution par frame de rendu (`sim.frame`). Une boucle de trente appels
  à `script.update` n'exécute **qu'une** frame. Passer par `handle.tick`.

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
- **Ne pas consigner l'état des push dans la documentation** : Théo s'en occupe,
  et l'information périme au premier `git push`. Pousser seulement quand il le
  demande.

## Refonte UX — règles actées

- **Cible : le panneau du haut de `atr-new-ui.png`** ("CAMTOOL 2.5", 3 colonnes colorées). Les captures du bas sont l'UI actuelle à onglets (Camera → violet, Transform → vert, Tracking → orange).
- **Vue unique, pas d'onglets** : tous les paramètres d'une caméra visibles en même temps (ATR perd du temps à changer d'onglet).
- **ISO fonctionnel** : la nouvelle UI couvre 100 % de `docs/ui-inventory.md`.
  Cette règle n'est vérifiable que si l'inventaire existe — le tenir à jour fait
  partie du travail de refonte, pas de la documentation d'après-coup. Tout élément absent de la maquette est un **oubli** et doit être réintégré. Aucun bouton, raccourci ou comportement supprimé sans accord explicite de Théo.
- **Saisie rapide souhaitée** : glisser la souris sur une valeur et saisie clavier directe, en plus des flèches. Attention : le clic sur la valeur est déjà le *toggle de keyframe* (voir inventaire) → choisir un autre geste et rendre visible l'état keyframé/non keyframé de chaque paramètre. Proposer le geste à Théo avant d'implémenter.
- Conserver les modificateurs Ctrl (pas ÷ 4) et Shift (pas × 4).
- **L'app doit continuer à piloter la caméra fenêtre fermée.** On regarde un
  replay sans vouloir un panneau à l'écran — c'est l'usage normal, pas un cas
  limite. Côté Lua : `LAZY = PARTIAL` (surtout pas `FULL`, qui décharge l'app à
  la fermeture de la fenêtre) + `[SIM_CALLBACKS] WORLD_UPDATE` pour le travail
  par frame. Contrepartie assumée : fermer la fenêtre alors qu'une caméra est
  tenue la laisse tenue ; il faut rouvrir l'app pour la relâcher.
