# Inventaire de l'UI CamTool 2

> **À quoi sert ce document.** `CLAUDE.md` pose la règle « ISO fonctionnel » :
> la nouvelle UI doit couvrir **100 %** de ce qui suit, et tout élément absent de
> la maquette ATR est un **oubli** à réintégrer, pas une simplification. Sans cet
> inventaire, cette règle n'est pas vérifiable.
>
> Il décrit **CamTool 2 tel qu'il est**, pas ce qu'il devrait être.

## Comment il a été établi, et ce qu'il vaut

Lecture de `CamTool_2.py` (2604 lignes), `ui/*.py` (8 widgets), `classes/hotkey.py`
et `classes/MouseLook.py`. Les éléments et leurs gestionnaires de clic ont été
extraits mécaniquement, donc la **liste** est exhaustive.

**Limites, à connaître avant de s'en servir :**

- L'UI n'a **jamais été observée en fonctionnement** pour écrire ce document. La
  disposition visuelle, la formulation exacte des libellés et le rendu sont
  déduits du code.
- Les comportements décrits viennent de la lecture du code, pas d'un test. Ceux
  marqués **⚠️ à confirmer** sont ceux où le code est ambigu.
- Les onglets `Settings` et `Spline` sont moins détaillés que les autres.

**Ce document doit être mis à jour pendant la refonte, pas après.**

---

## 1. Le modèle d'interaction — la partie qui compte

C'est ici que se joue la difficulté de la refonte. Presque tous les paramètres
sont un widget `Option` (`ui/option.py`), composé de :

```
[ Libellé ]  [ ◀ ]  [   valeur   ]  [ ⟲ ]  [ ▶ ]
                                     ^ optionnel
```

### Le clic sur la valeur bascule le keyframe

**Ce n'est pas un champ de saisie.** Cliquer sur la valeur centrale
**crée ou supprime le keyframe** du paramètre à la position courante
(`set_data`, action `toogle` — la faute de frappe est dans le code) :

| État du paramètre | Effet du clic |
|---|---|
| keyframé | la valeur passe à `None` → **le keyframe est supprimé** |
| non keyframé | **le keyframe est créé**, avec la valeur au niveau caméra |

C'est la contrainte que `CLAUDE.md` signale pour la refonte : le geste de saisie
rapide souhaité par ATR **ne peut pas être le clic**, déjà pris.

### Les flèches agissent sur deux niveaux différents

Selon que le paramètre est keyframé ou non, les mêmes flèches ne modifient pas la
même chose :

| État | Cible de ◀ ▶ | Pas appliqué |
|---|---|---|
| **keyframé** | la valeur du **keyframe** | `pas / 5` |
| **non keyframé** | la valeur au niveau **caméra** | `pas` entier |

Le facteur 5 entre les deux est dans le code, sans commentaire.
**⚠️ à confirmer** : intentionnel (réglage fin sur un keyframe) ou accident ?

### Modificateurs

| Touche | Effet sur le pas |
|---|---|
| **Ctrl** | ÷ 4 |
| **Shift** | × 4 |

Lus via `ctt.is_async_key_pressed("c"/"s")` — un des appels DLL restants.
`CLAUDE.md` impose de les conserver.

⚠️ **Collision à connaître** : en mouse look, **Shift = zoom avant** et
**Ctrl = zoom arrière** (`CamTool_2.py` ~85-92). Les mêmes touches servent donc à
deux choses selon le contexte.

### Bornage

Certains paramètres sont bornés à `[0, 1]`, d'autres non (argument `clamp`). Voir
les tableaux plus bas — la colonne est renseignée par paramètre.

---

## 2. En-tête

| Élément | Type | Comportement |
|---|---|---|
| `activate` | bouton | Active / désactive CamTool. Également sur **F10**. |
| `free_camera` | bouton | Bascule en caméra libre. |
| `title` | libellé | Titre + numéro de version. |
| `the_x` | libellé | Position courante sur la piste (0..1). |
| `mode-pos` | bouton | Mode **position** : caméras déclenchées par la position piste. |
| `mode-time` | bouton | Mode **temps**. |
| `header_replay_mm` | bouton | Replay : reculer (grand pas). |
| `header_replay_m` | bouton | Replay : reculer. |
| `header_jump_to_keyframe` | bouton | Sauter au keyframe. |
| `header_replay_p` | bouton | Replay : avancer. |

⚠️ **à confirmer** : les libellés exacts et le pas de chaque bouton de replay.

---

## 3. Panneaux latéraux

### Liste des caméras (`side_c`)

| Élément | Comportement |
|---|---|
| `icon_camera` | En-tête du panneau. |
| `cameras` | Liste sélectionnable des caméras. |
| `add` | Ajoute une caméra (`side_c__add_camera`). |
| `remove` | Supprime la caméra courante (`side_c__remove_camera`). |

### Liste des keyframes (`side_k`)

| Élément | Comportement |
|---|---|
| `icon_keyframe` | En-tête du panneau. |
| `keyframes` | Liste sélectionnable des keyframes. |
| `add` | Ajoute un keyframe (`side_k__add_keyframe`). |
| `remove` | Supprime le keyframe courant (`side_k__remove_keyframe`). |

### Navigation entre keyframes

Trois amplitudes de pas dans chaque sens, en mode `pos` :
`keyframes__pos_mmm` · `_mm` · `_m` · **`keyframes__pos`** · `_p` · `_pp` · `_ppp`

En mode `time`, deux seulement : `_mm` · `_m` · `keyframes__time` · `_p` · `_pp`.

⚠️ **Asymétrie à confirmer** : pourquoi trois amplitudes en `pos` et deux en
`time` ?

---

## 4. Onglets

Cinq onglets, exclusifs : **Camera** · **Transform** · **Tracking** · **Spline** ·
**Settings**.

La maquette ATR supprime les onglets au profit d'une vue unique — c'est le point
central de la refonte. Les trois premiers correspondent aux couleurs de la
maquette : Camera → violet, Transform → vert, Tracking → orange.
**Spline et Settings n'apparaissent pas dans la maquette : ce sont des oublis à
réintégrer.**

### Onglet Camera

| Paramètre | Type | Pas | Borné |
|---|---|---|---|
| `camera_in` | **saisie éditable** (`Editable_Button`) | — | — |
| `camera_pit` | bascule | — | — |
| `camera_focus_point` | option | ⚠️ à relever | ⚠️ |
| `camera_use_tracking_point` | bascule | — | — |
| `camera_fov` | option | ⚠️ à relever | ⚠️ |
| `camera_use_specific_cam` | option (flèches seules) | — | — |
| `camera_shake` | option | 0.1 | non |
| `camera_offset_shake` | option | 0.1 | non |

`camera_in` est le **seul champ à saisie clavier directe** de toute l'UI
(`camera__camera_in__show_input`). C'est un précédent utile pour la saisie rapide
demandée par ATR.

### Onglet Transform

| Paramètre | Pas | Borné | Reset |
|---|---|---|---|
| `loc_x` | 0.5 | non | — |
| `loc_y` | 0.5 | non | — |
| `loc_z` | 0.5 | non | — |
| `transform_loc_strength` | 0.25 (défaut) | oui | — |
| `rot_x` (pitch) | 2.5° | non | **oui** |
| `rot_y` (roll) | 2.5° | non | **oui** |
| `rot_z` (heading) | 2.5° | non | — |
| `transform_rot_strength` | 0.25 (défaut) | oui | — |

⚠️ `rot_x` et `rot_y` ont un bouton reset, **pas `rot_z`**. Asymétrie à confirmer.

Un libellé `lbl_rot_strength_exception` existe — une condition particulière est
affichée à l'utilisateur. ⚠️ Laquelle ?

### Onglet Tracking

| Paramètre | Pas | Borné |
|---|---|---|
| `car_1` | — | — |
| `car_2` | — | — |
| `tracking_mix` | 0.25 | oui |
| `tracking_offset` | 0.1 | non |
| `tracking_offset_pitch` | 0.5° | non |
| `tracking_offset_heading` | 1° | non |
| `tracking_strength_pitch` | 0.25 (défaut) | oui |
| `tracking_strength_heading` | 0.25 (défaut) | oui |

`car_1` et `car_2` sélectionnent les voitures suivies, `tracking_mix` dose entre
les deux.

### Onglet Spline

| Élément | Pas | Borné |
|---|---|---|
| `spline_record` | bouton d'enregistrement | — |
| `spline_speed` | 0.01 | non |
| `spline_affect_loc_xy` | 0.05 | oui |
| `spline_affect_loc_z` | ⚠️ | ⚠️ |
| `spline_affect_pitch` | ⚠️ | ⚠️ |
| `spline_affect_roll` | ⚠️ | ⚠️ |
| `spline_affect_heading` | ⚠️ | ⚠️ |
| `spline_offset_pitch` | ⚠️ | ⚠️ |
| `spline_offset_heading` | ⚠️ | ⚠️ |
| `spline_offset_loc_x` | ⚠️ | ⚠️ |
| `spline_offset_loc_z` | ⚠️ | ⚠️ |
| `spline_offset_spline` | ⚠️ | ⚠️ |

⚠️ `spline_record` est la **seule fonction d'écriture de données hors sauvegarde
de fichier** : elle enregistre une trajectoire de caméra. Son déroulé exact
(démarrage, arrêt, fréquence d'échantillonnage) reste à documenter.

### Onglet Settings

Contient au moins : `settings_smart_tracking`, et des réglages de `start_pos`,
`track`, `pit`, `size`. ⚠️ **Le moins bien couvert de cet inventaire.**

---

## 5. Chargement et sauvegarde

Un formulaire (`file_form`) avec :

| Élément | Comportement |
|---|---|
| `input` | Nom du fichier. |
| `save` | Sauvegarde ou charge (`file_form__save_or_load`). |
| `cancel` | Annule. |

Les fichiers sont nommés `<piste>_<layout>-<nom>.json` et **seuls ceux de la piste
courante sont proposés** (`files/data_files.py`).

---

## 6. Raccourcis clavier

| Touche | Action |
|---|---|
| **F10** | Activer CamTool |
| **F1, F2, F3, F5, F6, F7** | Désactiver CamTool (touches de caméra d'AC) |
| **Y, U, I, O, P** | Charger les fichiers de données 1 à 5 |

Les raccourcis Y/U/I/O/P sont **conditionnels** : enregistrés seulement si
`enable_hotkeys` est vrai dans `settings.json`, et retirés sinon
(`classes/hotkey.py`). Il existe donc un réglage pour les désactiver.

---

## 7. Souris

| Geste | Effet |
|---|---|
| Mouvement souris | Rotation de la caméra (mouse look) |
| **Shift** maintenu | Zoom avant, progressif |
| **Ctrl** maintenu | Zoom arrière, progressif |
| Bouton gauche | Modifie le comportement du mouse look ⚠️ |

Le zoom a une **inertie** : `release_factor` suit une courbe sinus à
l'enfoncement comme au relâchement (`MouseLook.zoom`), il ne s'arrête pas net.
À reproduire pour que le geste garde la même sensation.

---

## 8. Ce qui manque à cet inventaire

À compléter avant de considérer la règle « ISO fonctionnel » comme vérifiable :

1. **Onglet Settings** : contenu réel de chaque réglage.
2. **Pas et bornage** de tous les paramètres marqués ⚠️.
3. **Boutons de replay** de l'en-tête : libellés et amplitudes.
4. **`spline_record`** : déroulé complet de l'enregistrement.
5. **Libellés exacts** tels qu'affichés — ce document utilise les noms de code.
6. **Disposition visuelle** : ordre et regroupement réels à l'écran.
7. **États désactivés** : `Option` a `enable()`/`disable()`, mais les conditions
   qui grisent un paramètre n'ont pas été relevées.
8. **`lbl_rot_strength_exception`** : quelle condition déclenche ce message ?

Les points 1, 2 et 7 demandent surtout de la lecture de code. Les points 3, 5 et 6
demandent de **voir l'application tourner** — donc Théo, ou des captures.
