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
| ◆ losange orange | ⚠️ rôle inconnu |
| `CamTool v2.2.0 (1448 m)` | Titre, version, et **longueur du circuit en mètres** |
| 📍 épingle | Mode **position** (`pos.png` / `pos_active.png`) |
| ⏱ chronomètre | Mode **temps** (`time.png` / `time_active.png`) |
| ⏻ power | **Activer / désactiver** CamTool (`on.png` / `off.png`). Aussi **F10**. |

### Barre de position

```
[«] [‹]        157.06 m        [›] [»]
```

Suit le même code couleur que le reste :

- **Rouge** → un keyframe existe ici ; la valeur est celle **du keyframe**
- **Gris** → aucun keyframe ; la valeur est la position **vivante de la voiture**

Affichée en **mètres** en mode position, en **frames** en mode temps.

Quatre boutons de navigation : `«` et `»` (grand pas, images `prev+.png` /
`next+.png`), `‹` et `›` (petit pas). Le code expose **trois** amplitudes en mode
`pos` (`_m`, `_mm`, `_mmm`) mais deux seulement en mode `time`.
⚠️ La capture n'en montre que deux de chaque côté — la troisième amplitude est
peut-être accessible autrement (modificateur ?).

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

| Libellé | Valeur exemple | Pas | Borné |
|---|---|---|---|
| `Focus point:` | `500.00 m` | ⚠️ | ⚠️ |
| `Autofocus:` | `True` | bascule | — |
| `FOV:` | `8.70°` | ⚠️ | ⚠️ |
| `Specific cam:` | `Camtool` | flèches seules | — |

`Focus point` est **grisé quand `Autofocus` est à True** — une dépendance entre
champs à conserver.

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

`Pitch` et `Roll` ont un bouton reset, **pas `Heading`**. ⚠️ Asymétrie à
confirmer : voulue, ou oubli ?

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

| Libellé | Valeur exemple | Pas | Reset |
|---|---|---|---|
| **`Record`** | bouton pleine largeur | — | — |
| `Speed:` | `100%` | 0.01 | — |

**Strength**

| Libellé | Valeur | Pas |
|---|---|---|
| `Location XY:` | `100%` | 0.05 |
| `Location Z:` | `100%` | ⚠️ |
| `Pitch:` | `100%` | ⚠️ |
| `Roll:` | `100%` | ⚠️ |
| `Heading:` | `100%` | ⚠️ |

**Offset**

| Libellé | Valeur | Pas | Reset |
|---|---|---|---|
| `Pitch:` | `0.00°` | ⚠️ | — |
| `Heading:` | `0.00°` | ⚠️ | — |
| `Location X:` | `0.00 m` | ⚠️ | — |
| `Location Z:` | `0.00 m` | ⚠️ | — |
| `Spline:` | `0.00 m` | ⚠️ | **⟲** |

⚠️ **`Record`** est la seule fonction d'écriture de données hors sauvegarde de
fichier : elle enregistre une trajectoire de caméra. Son déroulé (démarrage,
arrêt, fréquence d'échantillonnage) reste à documenter.

### Onglet Settings

| Libellé | Type |
|---|---|
| **`Save`** | bouton pleine largeur |
| **`Load`** | bouton pleine largeur |
| `Load on startup:` | bascule (`True`) |
| `Enable hotkeys:` | bascule (`True`) |
| `Track spline:` | bouton **`Remove`** |
| `Pit spline:` | bouton **`Remove`** |
| **`Reset`** | bouton pleine largeur |

`Enable hotkeys` commande l'enregistrement des raccourcis Y/U/I/O/P
(`classes/hotkey.py`). `Load on startup` correspond à `load_last_used_data` dans
`settings.json`.

⚠️ `Reset` : portée exacte inconnue (la caméra ? toutes les caméras ? les
réglages ?). **À vérifier avant de le reproduire** — c'est potentiellement
destructif.

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
| Bouton gauche | Modifie le comportement du mouse look ⚠️ |

Le zoom a une **inertie** : `release_factor` suit une courbe sinus à
l'enfoncement comme au relâchement — il ne s'arrête pas net. À reproduire pour
conserver la sensation du geste.

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
| non keyframé (gris) | **keyframe créé**, avec la valeur au niveau caméra |

C'est la contrainte que `CLAUDE.md` signale : le geste de saisie rapide voulu par
ATR **ne peut pas être le clic**, déjà pris.

### Les flèches agissent sur deux niveaux

| État | Cible de ◀ ▶ | Pas |
|---|---|---|
| **keyframé** | la valeur du **keyframe** | `pas / 5` |
| **non keyframé** | la valeur au niveau **caméra** | `pas` entier |

Le facteur 5 est dans le code sans commentaire.
⚠️ Intentionnel (réglage fin sur un keyframe) ou accident ?

---

## 9. Ce qui manque encore

1. **Pas et bornage** des paramètres marqués ⚠️ (surtout l'onglet Spline).
2. **`Record`** : déroulé complet de l'enregistrement de spline.
3. **`Reset`** (Settings) : portée exacte. Potentiellement destructif.
4. **Le losange orange ◆** de l'en-tête : rôle inconnu.
5. **Troisième amplitude** de navigation en mode `pos` : le code l'expose, la
   capture n'en montre que deux.
6. **Asymétrie des resets** : Pitch et Roll en ont un, pas Heading.
7. **États désactivés** : seul `Focus point`/`Autofocus` est confirmé ; d'autres
   dépendances existent peut-être.
8. **Bouton gauche de la souris** pendant le mouse look : effet exact.

Tous relèvent désormais de la **lecture de code**, plus de l'observation — les
captures ont réglé les questions de libellés, d'unités, de couleurs et de
disposition.
