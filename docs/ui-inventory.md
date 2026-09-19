# Inventaire de l'UI CamTool 2

> **À quoi sert ce document.** `CLAUDE.md` pose la règle « ISO fonctionnel » :
> la nouvelle UI doit couvrir **100 %** de ce qui suit, et tout élément absent de
> la maquette ATR est un **oubli** à réintégrer, pas une simplification. Sans cet
> inventaire, cette règle n'est pas vérifiable.
>
> Il décrit **CamTool 2 tel qu'il est**, pas ce qu'il devrait être.

## Comment il a été établi

Lecture de `CamTool_2.py` (2604 lignes), `ui/*.py`, `classes/hotkey.py`,
`classes/MouseLook.py`, **plus cinq captures d'écran des cinq onglets fournies
par Théo** (version 2.2.0). Les éléments et leurs gestionnaires de clic ont été
extraits mécaniquement : la liste est exhaustive. Les libellés, unités et
couleurs viennent des captures et sont recoupés avec le code.

Ce qui reste incertain est marqué **⚠️**.

---

## 1. Lecture d'écran — le code couleur

**C'est la clé de toute l'interface, et elle tient en une règle.** Il n'existe que
deux couleurs de fond (`ui/button.py`) :

| Couleur | Signifie | Valeur affichée |
|---|---|---|
| **Rouge** `(0.75, 0.1, 0.1)` | le paramètre **est keyframé** au keyframe courant | celle du **keyframe** |
| **Gris** `(0.5, 0.5, 0.5)` | il **n'est pas keyframé** | la valeur **vivante** de la caméra |

Vérifié dans le code (`CamTool_2.py` ~1114-1160) : si
`interpolation[param] == None`, on retombe sur la valeur caméra et on passe en
gris ; sinon rouge.

**Conséquence pour la refonte** : la règle UX « rendre visible l'état
keyframé/non keyframé » de `CLAUDE.md` est **déjà satisfaite** par ce fond rouge.
Il ne s'agit pas d'inventer un indicateur, mais de ne pas perdre celui-ci.

⚠️ **Piège de lecture des captures** : les boutons sont **semi-transparents** et
le replay transparaît derrière. Un paramètre gris posé sur une carrosserie jaune
paraît olive (`Heading`, `Specific cam` sur les captures). Il n'y a pas de
troisième état. **C'est un défaut de lisibilité à corriger dans la refonte.**

Un état désactivé existe en plus : `disable()` ne change que l'opacité du texte
(alpha 0.5), pas le fond — voir `Focus point` grisé quand `Autofocus` est à True.

### Unités

Les valeurs sont **affichées en unités réelles**, alors qu'elles sont **stockées
normalisées** (voir `docs/legacy.md`) :

| Affiché | Stocké |
|---|---|
| mètres (`157.06 m`) | position piste 0..1 × longueur du circuit |
| degrés (`8.70°`) | radians, et pour le FOV la forme convertie `1/(fov+15)` |
| pourcents (`100%`) | 0..1 |
| frames (mode temps) | millisecondes / taux de rafraîchissement |

La conversion est faite à l'affichage (`set_text(valeur, …, "m"/"degrees")`).

---

## 2. En-tête

```
[📹] ◆ CamTool v2.2.0 (1448 m)            [📍] [⏱] [⏻]
```

| Élément | Comportement |
|---|---|
| 📹 icône caméra | **Activate Free Camera** (libellé confirmé par l'infobulle) |
| ◆ losange orange | **Pas un widget CamTool** — voir ci-dessous |
| `CamTool v2.2.0` | Titre et version |
| `(1448 m)` | **Position courante de la voiture**, en mètres. En mode temps : secondes. Vide si indisponible. ⚠️ Ce n'est *pas* la longueur du circuit. |
| 📍 épingle | Mode **position** (`pos.png` / `pos_active.png`) |
| ⏱ chronomètre | Mode **temps** (`time.png` / `time_active.png`) |
| ⏻ power | **Activer / désactiver** CamTool (`on.png` / `off.png`). Aussi **F10**. |

### Le losange orange n'appartient pas à CamTool

`__create_header` construit exactement six éléments : `free_camera`, `title`,
`the_x`, `activate`, `mode-pos`, `mode-time`. Aucun losange, et aucun autre
endroit du code ne dessine dans l'en-tête. L'icône de l'app
(`content/gui/icons/CamTool_2_ON.png`) est une caméra rouge, pas un losange.

C'est donc un élément du **cadre de fenêtre d'Assetto Corsa**, pas de
l'application. Rien à reproduire dans la refonte.

### Barre de position

```
[«] [‹]        157.06 m        [›] [»]
```

Suit le même code couleur que le reste :

- **Rouge** → un keyframe existe ici ; la valeur est celle **du keyframe**
- **Gris** → aucun keyframe ; la valeur est la position **vivante de la voiture**

Affichée en **mètres** en mode position, en **frames** en mode temps.

Quatre boutons de navigation entre **keyframes** : `«` et `»` (grand pas, images
`prev+.png` / `next+.png`), `‹` et `›` (petit pas). Deux amplitudes de chaque
côté, dans les deux modes.

**Attention au code mort** : `keyframes__pos_mmm` et `_ppp` (une troisième
amplitude) sont définis mais **branchés à aucun bouton**. De même, les boutons de
replay de l'en-tête (`header_replay_mm`, `header_jump_to_keyframe`…) sont
**entièrement en commentaire** (`CamTool_2.py` ~262-265) : ils n'existent pas dans
l'application. Un `grep` naïf les fait apparaître — ils ne sont pas à réintégrer.

---

## 3. Panneaux latéraux

Deux colonnes numérotées à gauche, côte à côte :

| Colonne | Contenu |
|---|---|
| **1re** | Les **caméras**, numérotées 1..N, avec `-` en tête et `+` en pied |
| **2e** | Les **keyframes** de la caméra sélectionnée, mêmes commandes |

La sélection courante est en **rouge**, cohérente avec le code couleur général
(`highlight(True)` sur l'élément actif).

Sur les captures : 11 caméras, et 2 keyframes pour la caméra 1. `-` supprime,
`+` ajoute.

---

## 4. Onglets

Cinq onglets exclusifs, empilés verticalement : **Camera** · **Transform** ·
**Tracking** · **Spline** · **Settings**.

La maquette ATR les supprime au profit d'une vue unique — c'est le cœur de la
refonte. Elle ne couvre que les trois premiers (Camera → violet, Transform →
vert, Tracking → orange). **Spline et Settings n'y figurent pas : ce sont des
oublis à réintégrer**, pas des suppressions.

### Onglet Camera

**Activation**

| Libellé | Valeur exemple | Type | Pas |
|---|---|---|---|
| `Camera in:` | `149.98 m` | **saisie clavier** | — |
| `Pit only:` | `True` | bascule | — |

`Camera in` est le **seul champ à saisie clavier directe** de toute l'UI. C'est le
précédent à reprendre pour la saisie rapide voulue par ATR.

**Camera**

| Libellé | Valeur exemple | Pas (non keyframé) | Pas (keyframé) | Borné |
|---|---|---|---|---|
| `Focus point:` | `500.00 m` | **× 0.9 / × 1.1** | ± 0.5 m | ≥ 0 |
| `Autofocus:` | `True` | bascule | — | — |
| `FOV:` | `8.70°` | ± 5° | ± 0.5° | ≥ 0 |
| `Specific cam:` | `Camtool` | −1 → 13, cyclique | — | — |

`Focus point` est **grisé quand `Autofocus` est à True** — une dépendance entre
champs à conserver. C'est la **seule** de toute l'application : `disable()`
n'est appelé qu'une fois dans les 2600 lignes de `CamTool_2.py`.

#### Ces deux-là ne suivent pas la règle générale

`Focus point` et `FOV` ne passent pas par `set_data` mais par des branches
écrites à la main dans `on_click__camera`. Trois conséquences, toutes à
trancher avant de les reproduire :

- **Le pas du focus est multiplicatif** hors keyframe : `max(0, f − f × 0.1)`
  et `f + f × 0.1`. Donc **un focus à 0 y reste pour toujours** — les flèches
  ne peuvent plus le faire remonter. Piège réel.
- **Ni Ctrl ni Shift n'agissent** sur ces deux champs : les modificateurs
  ÷ 4 / × 4 sont lus dans `set_data` et `set_camera_data`, pas ici.
- **Le facteur de réglage fin n'est pas le même** : ailleurs c'est le pas
  divisé par 5 ou par 10 (voir §8) ; ici c'est un second pas écrit en dur.

Sur `FOV` keyframé, la valeur est décodée en degrés, modifiée de ± 0.5, puis
ré-encodée. Descendre à 0 par ce chemin stocke la sentinelle `0.00001` de
`convert_fov_2_focal_length`, qui se relit en `0.00001` et non en `0` — la
seule façon connue d'atteindre cette asymétrie depuis l'UI.

`Specific cam` parcourt **−1 à 13** en boucle, `−1` étant `Camtool`. Les
valeurs 0 à 13 désignent une caméra d'Assetto Corsa à laquelle CamTool 2 passe
la main sans rien interpoler ; onze caméras de référence sont dans ce cas.

**Shake**

| Libellé | Valeur exemple | Pas | Borné |
|---|---|---|---|
| `Camera:` | `0%` | 0.1 | non |
| `Tracking:` | `0%` | 0.1 | non |

Ce sont `camera_shake_strength` et `camera_offset_shake_strength`. Rappel de
`docs/legacy.md` : **seul le premier est interpolé**, le second est lu au niveau
caméra — c'est l'élément concret de l'issue **#25**.

### Onglet Transform

**Location**

| Libellé | Valeur exemple | Pas | Borné | Reset |
|---|---|---|---|---|
| `X:` | `-173.31 m` | 0.5 | non | — |
| `Y:` | `448.16 m` | 0.5 | non | — |
| `Z:` | `33.40 m` | 0.5 | non | — |
| `Strength:` | `100%` | 0.25 | oui | — |

**Rotation**

| Libellé | Valeur exemple | Pas | Borné | Reset |
|---|---|---|---|---|
| `Pitch:` | `0.76°` | 2.5° | non | **⟲** |
| `Roll:` | `-0.00°` | 2.5° | non | **⟲** |
| `Heading:` | `175.45°` | 2.5° | non | — |
| `Strength*:` | `100%` | 0.25 | oui | — |

Une note de bas de panneau : **`*except roll`**. La force de rotation s'applique
donc au pitch et au heading mais **pas au roll**. C'est
`lbl_rot_strength_exception`, dont je cherchais le sens.

`Pitch` et `Roll` ont un bouton reset, **pas `Heading`** — et ce sont les seuls
de toute l'UI avec `Spline:` dans l'onglet Spline.

Le reset remet la valeur à **0**, en respectant les deux niveaux : sur le
keyframe s'il est keyframé, sur la caméra vivante sinon.

L'absence de reset sur le cap est probablement **délibérée** : pitch 0 (horizon)
et roll 0 (droit) sont des repères utiles, alors qu'un cap 0 pointerait vers un
axe arbitraire du monde. *(Inférence, pas une certitude.)*

### Onglet Tracking

**Tracking**

| Libellé | Valeur exemple | Pas | Borné |
|---|---|---|---|
| `Active car:` | `Player` | — | — |
| `Mix:` | `0%` | 0.25 | oui |
| `Extra car:` | `Player` | — | — |

**Offset**

| Libellé | Valeur exemple | Pas | Borné |
|---|---|---|---|
| `Tracking:` | `-0.10` | 0.1 | non |
| `Pitch:` | `0.00°` | 0.5° | non |
| `Heading:` | `0.00°` | 1° | non |

`Tracking` est le seul paramètre affiché **sans unité**. C'est `tracking_offset`,
qui dose l'anticipation : négatif = la caméra vise devant la voiture, positif =
derrière (voir `docs/legacy.md`). La valeur `-0.10` est celle de **76 %** des
caméras de référence.

**Strength**

| Libellé | Valeur exemple | Pas | Borné |
|---|---|---|---|
| `Pitch:` | `100%` | 0.25 | oui |
| `Heading:` | `100%` | 0.25 | oui |

### Onglet Spline

| Libellé | Valeur exemple | Pas | Borné | Reset |
|---|---|---|---|---|
| **`Record`** | bouton **tri-état** pleine largeur | — | — | — |
| `Speed:` | `100%` | 0.05 | non | — |

**Strength** — tous bornés à [0, 1], pas de 0.1

| Libellé | Paramètre |
|---|---|
| `Location XY:` | `spline_affect_loc_xy` |
| `Location Z:` | `spline_affect_loc_z` |
| `Pitch:` | `spline_affect_pitch` |
| `Roll:` | `spline_affect_roll` |
| `Heading:` | `spline_affect_heading` |

**Offset**

| Libellé | Pas | Borné | Reset |
|---|---|---|---|
| `Pitch:` | 1° | non | — |
| `Heading:` | 5° | non | — |
| `Location X:` | 0.25 | non | — |
| `Location Z:` | 0.25 | non | — |
| `Spline:` | **5 m en mode position, 10 en mode temps** | non | **⟲** |

Le pas de `Spline` est exprimé en **unités réelles puis converti** :
`5 / ac.getTrackLength()` en mode position. Le pas ressenti est donc le même quel
que soit le circuit — à reproduire.

### L'enregistrement de trajectoire

`Record` suit le même motif tri-état que les boutons de spline des Settings :
**Record → Stop → Remove → Record**.

Pendant l'enregistrement (`Camera.record_spline`), à chaque échantillon sont
capturés la position (3 axes), le pitch, le roll et le cap de la caméra, plus la
position piste.

Trois détails qui comptent pour le portage :

- **Cadence** : un échantillon par seconde de *temps de replay*
  (`dt * replayTimeMultiplier`), pas de temps réel — la densité le long de la
  piste ne dépend donc pas de la vitesse de lecture.
  ⚠️ Les splines de référence sont plus denses que cette règle ne le laisse
  attendre (31 points sur ~5 % d'un tour de Silverstone). À éclaircir.
- **Bouclage de tour** : `if abs(x - prev) > abs(x + 1 - prev): x += 1`.
  **C'est là que naissent les `the_x > 1`** observés dans les fichiers, et donc
  ce qui justifie le déballage de `spline.queryPosition`.
- **Le cap est déroulé à l'enregistrement** (`normalize_angle` contre
  l'échantillon précédent), donc les valeurs stockées sont continues, sans saut à
  ±π. C'est ce qui permet de les interpoler directement.

### Onglet Settings

| Libellé | Type |
|---|---|
| **`Save`** | bouton pleine largeur |
| **`Load`** | bouton pleine largeur |
| `Load on startup:` | bascule (`True`) |
| `Enable hotkeys:` | bascule (`True`) |
| `Track spline:` | bouton **tri-état** (voir ci-dessous) |
| `Pit spline:` | bouton **tri-état** |
| **`Reset`** | bouton pleine largeur |

`Enable hotkeys` commande l'enregistrement des raccourcis Y/U/I/O/P
(`classes/hotkey.py`). `Load on startup` correspond à `load_last_used_data` dans
`settings.json`.

**Les boutons de spline sont tri-état** : un seul bouton dont le libellé annonce
ce qu'il va faire.

```
  aucune spline  →  [Record]  → clic → enregistrement en cours → [Stop]
  enregistrement →  [Stop]    → clic → arrêt → [Remove] (ou [Record] si vide)
  spline existante → [Remove] → clic → suppression → [Record]
```

La capture montre `Remove` parce que Théo a déjà des splines de piste et de
stand enregistrées. Ce sont les splines **de piste** (`track_spline`,
`pit_spline`), distinctes des splines **par caméra** de l'onglet Spline.

### ⚠️ `Reset` est totalement destructif

`data.reset()` remplace **les deux listes de caméras** (`pos` *et* `time`) par
une unique caméra vide, **et** vide les splines de piste et de stand.

```python
def reset(self):
    self.mode = {"pos": [Camera_Data(0)], "time": [Camera_Data(0)]}
    self.pit_spline  = {…vide…}
    self.track_spline = {…vide…}
```

**Aucune confirmation n'est demandée**, et CamTool 2 n'a pas d'annulation. Un
clic accidentel détruit tout le travail non sauvegardé. À reproduire **avec une
confirmation**, et c'est un argument de plus pour la pile d'annulation prévue
dans `CLAUDE.md`.

---

## 5. Chargement et sauvegarde

Le formulaire s'ouvre **à droite du panneau principal** :

```
[ init          ]  [ Load ] [ Cancel ]
─────────────────────────────────────
  init                            [✕]
```

| Élément | Comportement |
|---|---|
| champ texte | Nom du fichier |
| `Load` | Charge (ou `Save` selon l'entrée) |
| `Cancel` | Ferme le formulaire |
| liste | Fichiers disponibles **pour la piste courante** |
| `✕` | Supprime le fichier de la liste |

Les fichiers sont nommés `<piste>_<layout>-<nom>.json` et seuls ceux de la piste
courante sont proposés (`files/data_files.py`).

---

## 6. Raccourcis clavier

| Touche | Action |
|---|---|
| **F10** | Activer CamTool |
| **F1, F2, F3, F5, F6, F7** | Désactiver (les touches de caméra d'AC) |
| **Y, U, I, O, P** | Charger les fichiers de données 1 à 5 |

Y/U/I/O/P sont **conditionnels** : enregistrés seulement si `Enable hotkeys` est
vrai, retirés sinon.

---

## 7. Souris et modificateurs

| Geste | Effet |
|---|---|
| Mouvement souris | Rotation de la caméra (mouse look) |
| **Shift** maintenu | Zoom avant, progressif |
| **Ctrl** maintenu | Zoom arrière, progressif |
| **Bouton gauche maintenu** | **Pilote la rotation** |
| Bouton gauche relâché | La caméra **continue sur son inertie** |

### Le lissage existe déjà, et ce n'est pas un lissage exponentiel

`MouseLook` conserve un tableau des **60 dernières positions de souris**
(`__array_size = 60`, soit une seconde à 60 fps) et pilote la caméra avec leur
**moyenne**. C'est de là que vient la douceur du geste.

Le bouton gauche commande la mise à jour de ce tableau :

- **maintenu** → le tableau se remplit, la caméra suit la souris
- **relâché** → le tableau se fige, la moyenne reste, **la caméra continue sur
  son élan** et s'arrête progressivement

Cela corrige une réserve notée plus tôt dans `docs/etat.md` : le portage envoie
le delta souris brut, et j'avais supposé qu'un lissage exponentiel suffirait.
**Mieux vaut reproduire la moyenne glissante sur 60 échantillons**, qui est ce
que les vidéastes ont dans les mains.

Le zoom a en plus sa propre inertie : `release_factor` suit une courbe sinus à
l'enfoncement comme au relâchement — il ne s'arrête pas net.

### Dans les panneaux, les mêmes touches font autre chose

| Touche | Effet sur le pas |
|---|---|
| **Ctrl** | ÷ 4 |
| **Shift** | × 4 |

⚠️ **Collision de sémantique** : Shift et Ctrl valent ×4 / ÷4 dans les panneaux,
mais zoom avant / arrière en mouse look. `CLAUDE.md` impose de conserver les
modificateurs — donc de conserver aussi cette ambiguïté, ou de la lever
explicitement avec Théo.

---

## 8. Le modèle d'interaction — ce qui contraint la refonte

Presque tout paramètre est un widget `Option` :

```
[ Libellé ]  [ ◀ ]  [   valeur   ]  [ ⟲ ]  [ ▶ ]
                                     ^ optionnel
```

### Le clic sur la valeur bascule le keyframe

**Ce n'est pas un champ de saisie.** Cliquer sur la valeur centrale crée ou
supprime le keyframe du paramètre (`set_data`, action `toogle` — la faute de
frappe est dans le code) :

| État | Effet du clic |
|---|---|
| keyframé (rouge) | valeur mise à `None` → **keyframe supprimé** |
| non keyframé (gris) | **keyframe créé**, avec la valeur au niveau caméra *ou* la valeur vivante de la caméra selon le paramètre — voir le tableau plus bas |

C'est la contrainte que `CLAUDE.md` signale : le geste de saisie rapide voulu par
ATR **ne peut pas être le clic**, déjà pris.

### Les flèches agissent sur deux niveaux

| État | Cible de ◀ ▶ | Pas |
|---|---|---|
| **keyframé** | la valeur du **keyframe** | `pas / 5` (`set_data`) ou `pas / 10` (`set_camera_data`) |
| **non keyframé** | la valeur au niveau **caméra** | `pas` entier |

**Il y a deux diviseurs, pas un.** `set_data` divise par 5, `set_camera_data`
— utilisé par tout l'onglet Spline — divise par 10. Deux chiffres différents
dans deux fonctions qui font la même chose : la question « intentionnel ou
accident ? » penche nettement du côté de l'accident. **À unifier dans la
refonte, avec l'accord de Théo** : ça change la sensation de réglage sur des
caméras existantes.

Ctrl (÷ 4) et Shift (× 4) s'appliquent dans les deux fonctions, aux deux
niveaux — mais **pas** à `Focus point` ni à `FOV`, qui ont leur propre code.

#### Le pas de chaque paramètre

Relevé exhaustif des appels. « Borné » signifie ramené dans 0..1.

| Paramètre | Pas | Borné | Valeur à la création du keyframe |
|---|---|---|---|
| `loc_x` `loc_y` `loc_z` | 0.5 m | non | **position vivante de la caméra** |
| `rot_x` `rot_y` `rot_z` | 2.5° | non | **orientation vivante de la caméra** |
| `transform_rot_strength` | 0.25 | oui | niveau caméra |
| `transform_loc_strength` | 0.25 | oui | niveau caméra |
| `tracking_strength_pitch` | 0.25 | oui | niveau caméra |
| `tracking_strength_heading` | 0.25 | oui | niveau caméra |
| `tracking_offset` | 0.1 | non | niveau caméra |
| `tracking_offset_pitch` | 0.5° | non | niveau caméra |
| `tracking_offset_heading` | 1° | non | niveau caméra |
| `tracking_mix` | 0.25 | oui | niveau caméra |
| `camera_shake_strength` | 0.1 | non | niveau caméra |
| `camera_offset_shake_strength` | 0.1 | non | niveau caméra |
| `spline_speed` | 0.05 | non | niveau caméra |
| `spline_affect_loc_xy` `_loc_z` | 0.1 | oui | niveau caméra |
| `spline_affect_pitch` `_roll` `_heading` | 0.1 | oui | niveau caméra |
| `spline_offset_pitch` | 1° | non | niveau caméra |
| `spline_offset_heading` | 5° | non | niveau caméra |
| `spline_offset_loc_x` `_loc_z` | 0.25 m | non | niveau caméra |
| `camera_focus_point` | voir onglet Camera | ≥ 0 | **focus vivant de la caméra** |
| `camera_fov` | voir onglet Camera | ≥ 0 | **FOV vivant de la caméra** |

⚠️ Créer un keyframe ne prend donc pas toujours « la valeur au niveau
caméra ». Pour la position, la rotation, le focus et le FOV, il prend **la
valeur vivante de la caméra** lue à l'instant du clic (`ctt.get_position`, `get_pitch`, `get_roll`,
`get_heading`, `get_focus_point`, `get_fov`). C'est ce qui rend le geste
utile : on place la caméra, puis on clique pour la figer.

---

## 9. Ce qui manque encore

Un seul point, et il demande le jeu.

### Cadence d'échantillonnage des splines

La règle du code est nette et n'a **jamais changé** : `record_spline` est
appelé une fois par frame depuis `Camera.refresh` avec `dt × replayTimeMultiplier`,
accumule, et prend un échantillon quand le total dépasse 1 — soit **un
échantillon par seconde de temps de replay**. La ligne est celle de kasperski,
importée le 7 août 2021 et jamais retouchée depuis (`git log -S`).

Les fichiers de référence en contiennent 6 à 8 fois plus. Mesuré en croisant
les splines de `ks_silverstone_gp-seb.json` avec le temps que la voiture met
réellement à parcourir chaque portion, relevé dans une trace enregistrée :

| caméra | points | portion de tour | temps de replay | attendu à 1/s |
|---|---|---|---|---|
| 2 | 31 | 0.0031 → 0.0512 | 3.7 s | ~4 |
| 3 | 35 | 0.0527 → 0.1114 | 5.3 s | ~5 |
| 4 | 47 | 0.1132 → 0.1930 | 12.3 s | ~12 |
| 5 | 39 | 0.1947 → 0.2622 | 5.5 s | ~6 |
| 13 | 44 | 0.8467 → 0.9326 | 11.4 s | ~11 |

Deux hypothèses sont **éliminées** : le code n'a pas changé depuis que ces
fichiers ont été créés, et `record_spline` n'est pas appelé plusieurs fois par
frame.

Il en reste une seule, et elle est vérifiable en quinze secondes de jeu : **que
vaut `replayTimeMultiplier` en ralenti ?** Si Assetto Corsa y répond par un
nombre **supérieur** à 1 — un facteur d'étirement du temps plutôt qu'une
vitesse — alors filmer au ralenti accumule plus vite pendant que la voiture
avance moins, et la densité observée s'explique exactement. Si la valeur est
inférieure à 1, la densité est invariante à la vitesse de replay et il faudra
chercher ailleurs.

**Le test** : enregistrer une trace (`dev_record_trace`) en mettant le replay
au ralenti pendant quelques secondes. Le champ `rtm` de chaque frame donne la
réponse directement, sans rien instrumenter de plus.

### Pièges relevés, à ne pas reproduire

- **Code mort** : les boutons de replay de l'en-tête sont commentés, et la
  troisième amplitude de navigation (`_mmm` / `_ppp`) n'est branchée à rien. Un
  `grep` les fait apparaître comme s'ils existaient.
- **`Reset` sans confirmation** détruit les deux listes de caméras et les deux
  splines de piste, sans annulation possible.
- **Transparence des panneaux** : le replay transparaît derrière les valeurs et
  fausse la lecture des couleurs.
- **Shift / Ctrl ont deux sens** selon qu'on est dans les panneaux (× 4 / ÷ 4) ou
  en mouse look (zoom avant / arrière).
- **Un `Focus point` tombé à 0 ne remonte plus** : son pas est multiplicatif
  (× 0.9 / × 1.1), donc les flèches ne peuvent plus rien en faire.
- **`Focus point` et `FOV` ignorent Ctrl et Shift**, seuls de toute l'UI.
- **Deux diviseurs de réglage fin** coexistent, `/ 5` et `/ 10`, selon la
  fonction qui traite le paramètre.
