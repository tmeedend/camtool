---
description: Règles d'interaction de l'UI CamTool 3 — gestes, keyframes, infobulles
paths:
  - "apps/lua/CamTool3/ui/**"
---
<!--
  Écrit par le designer UX d'ATR, adopté tel quel. Les seules modifications :
  le chemin du frontmatter (le dossier réel n'a pas de tiret bas) et cette
  note.

  C'est un CONTRAT, pas un compte rendu : il dit ce que l'UI doit faire, pas
  ce qu'elle fait. L'état d'avancement est dans docs/etat.md.
-->

# Interactions UI — CamTool 3

Règles à appliquer à **tout** champ de paramètre. Elles priment sur l'habitude de câbler chaque champ à la main.

## Un seul composant paramètre

Tous les champs `< valeur >` (les 21 des colonnes Camera / Transform / Tracking, plus tout nouveau) passent par **un composant unique**. On n'écrit jamais un champ à la main. Ajouter un paramètre = un appel de plus, jamais une nouvelle gestion d'événements.

Anatomie d'une ligne :

```
◆ LABEL
< valeur unité >
```

- Losange à gauche du label : état de keyframe, cliquable.
- Flèches : pas unitaire.
- Zone centrale : glisser et double-clic.
- L'unité est toujours affichée (m, deg, %).

## Gestes — contrat, ne pas dévier

| Geste | Effet |
|---|---|
| Clic sur le losange | crée / supprime le keyframe du paramètre à la position courante |
| Clic sur une flèche | un pas |
| Glisser horizontalement sur la valeur | variation continue |
| Double-clic sur la valeur | saisie clavier |
| Clic droit pendant un glissé | annule, restaure la valeur d'avant |
| Clic ailleurs pendant une saisie | abandonne ce qui était tapé |
| Ctrl maintenu | pas ÷ 4 |
| Shift maintenu | pas × 4 |

> ⚠️ **Écart assumé avec le contrat d'origine, tranché par Théo en jeu.** Le
> contrat demandait Échap pour annuler un glissé ou une saisie. Dans Assetto
> Corsa, **Échap quitte le replay** : l'app peut retenir la touche pendant
> qu'un champ est ouvert (`ui.captureKeyboard`), et ça marche, mais ça
> entraîne la main à chercher Échap dans une application où la même touche,
> un instant plus tard sans champ ouvert, met fin à la session **avec toutes
> les caméras non sauvegardées**. Un geste d'annulation ne vaut pas ça. Échap
> est donc laissé au jeu, et l'annulation passe par le clic droit (glissé) ou
> le clic ailleurs (saisie).

**La molette ne modifie jamais une valeur.** Elle est réservée au défilement de la fenêtre. Un scroll ne permet pas de distinguer l'intention, et comme les champs défilent sous le curseur pendant le geste, un seul coup de molette pourrait modifier plusieurs paramètres sans que rien ne le signale. Aucune exception, même derrière un modificateur.

## Détails du glissé

- **Horizontal uniquement.** Un glissé vertical serait ambigu avec le défilement.
- **Zone morte** d'environ 4 px avant que le glissé ne prenne effet : un clic qui ripe ne doit rien changer.
- **Curseur** en flèche horizontale au survol d'une valeur modifiable (ImGui : `ImGuiMouseCursor_ResizeEW`). C'est ce qui rend le glissé découvrable, bien mieux qu'une ligne d'aide.
- Sensibilité proportionnelle à la plage du paramètre ; Ctrl et Shift s'appliquent comme aux flèches.
- Un champ désactivé (grisé) n'est ni glissable ni saisissable, et son curseur ne change pas.

## Undo

- **Un glissé = une seule entrée d'undo**, validée à la fin du geste, avec la valeur d'avant le début (ImGui : `IsItemDeactivatedAfterEdit`). Jamais une entrée par frame : cela noierait la pile.
- Idem pour une saisie clavier : une entrée à la validation.
- Toute modification passe par le point d'entrée unique existant. Ne jamais écrire directement dans les données de caméra depuis le code d'UI.

## Losanges

- **Plein** : keyframé ici. **Creux** : keyframé ailleurs dans cette caméra. **Vide** : jamais keyframé.
- Un paramètre animé doit rester repérable sans fixer le losange : teinter légèrement le champ.

## Aide et infobulles

Le bloc d'explications en bas de fenêtre est supprimé. Il est remplacé par :

1. ~~**Une infobulle par élément.**~~ **Une phrase par élément**, qui dit d'abord **ce que fait le paramètre**, puis les gestes utiles. Priorité aux noms cryptiques : `STRENGTH LO.`, `STRENGTH RO.`, `OFF TRACKING`, `STR PITCH`, `STR HEADING`, `MIX`, `AF`.
2. ~~**Un délai avant affichage.**~~ Sans objet.
3. **Une ligne de statut contextuelle**, une seule, en bas de la fenêtre : décrit ce qui est sous le curseur. Toujours visible, donc découvrable — contrairement à une infobulle, qu'il faut savoir aller chercher. **C'est le seul canal** : elle porte le nom de l'élément, sa phrase et ses gestes.
4. **Un bouton `?`** affichant la légende complète (losanges, code couleur du bandeau, raccourcis). Seul endroit où l'aide est exhaustive.

> ⚠️ **Écart assumé avec le contrat d'origine, tranché par Théo en jeu.** Le
> contrat demandait une infobulle par élément, avec un délai. **Il n'y en a
> plus aucune.** Une bulle s'affiche *par-dessus* le panneau qu'elle explique,
> et ce qu'elle recouvre est la ligne sous le curseur et ses voisines —
> c'est-à-dire précisément ce qu'on regarde pendant qu'on glisse une valeur.
> Une aide qui cache le travail n'est pas une aide.
>
> Aucune phrase n'a été perdue : les 32 sont écrites, et elles vont à la ligne
> de statut, toujours à l'écran, qui ne coûte pas un pixel de hauteur et ne
> recouvre rien. Le point 3 devient le canal unique au lieu d'être le second.
> Un test balaie le panneau entier et échoue si quoi que ce soit affiche
> encore une bulle.

Les noms de fonctions varient selon le binding Lua de CSP : vérifier dans le SDK avant de reprendre les noms C++ cités ici.

## Le ruban — la surface de navigation principale

<!--
  Section ajoutée après coup : le contrat d'origine a été écrit avant que le
  ruban et la carte existent. Les gestes ci-dessous ont été demandés par Théo,
  qui a tranché explicitement contre la version précédente ; les raisons sont
  les siennes et sont écrites ici pour qu'on ne les redécouvre pas.
-->

Le ruban est **le** navigateur : c'est lui qu'on regarde pour savoir où on en
est dans le tour. La carte dit la même chose dans l'espace ; elle ne commande
pas le replay.

**Deux zones horizontales, et le fond les distingue.** C'est le fond qui fait
le travail : il rend la coupure évidente sans un mot d'explication, ce qu'une
coupure expliquée n'obtient jamais.

| Zone | Contenu | Ce qu'on y fait |
|---|---|---|
| **La règle**, en haut, une quinzaine de pixels | Graduations de distance sur le tour, noms des portions quand le circuit en donne (`sections.ini`) | On déplace la tête de lecture |
| **Les segments**, en dessous | Une teinte par caméra, les losanges de la caméra éditée | On choisit une caméra |

> La règle fait 16 px et non la dizaine demandée : une ligne de texte en fait
> 13, et une règle sur laquelle on ne peut pas écrire une distance est une
> rangée de marques qui ne mesurent rien.

**Un nom l'emporte sur un chiffre.** Les deux ne tiennent pas sur la même
ligne. Là où le circuit a nommé la portion, la distance abandonne son
étiquette et garde sa marque — on lit le chiffre sur les marques voisines.

### La tête de lecture

Un trait vertical traversant les deux zones, avec une poignée triangulaire
dans la règle. Elle suit la lecture du replay toute seule.

| Geste | Effet |
|---|---|
| Clic ou glissé **n'importe où sur la règle** | Déplace la tête de lecture |
| Glisser la poignée | Pareil — c'est le même geste, la poignée dit seulement où est la tête |

**N'importe où, et c'est toute la règle.** Viser cinq pixels de triangle avant
que quoi que ce soit ne bouge est une épreuve d'adresse, pas un geste. Tous
les logiciels de montage laissent tirer la règle entière.

Pendant le glissé, le replay suit **grossièrement** : un saut par tranche de
100 ms, une seule sonde, aucune convergence. La recherche ordinaire sonde à
chaque frame jusqu'à tomber juste — soit soixante repositionnements par
seconde pendant un glissé, et pour rien, puisque le pointeur a bougé entre
temps. Un atterrissage faux reste en place jusqu'au tick suivant ; d'ici là la
boucle de frame a noté où on avait atterri, donc la correction est mieux
informée qu'une seconde sonde ne l'aurait été. **L'atterrissage exact a lieu
une fois, au relâchement** — c'est aussi le moment où être à quelques mètres
près commence à compter.

**Le son est coupé pour tout le geste**, pas pour chaque saut : CamTool 2
avait des artefacts sur les changements de position, et les rejouer une fois
par saut serait pire que ce qu'on évite.

### Les segments

| Geste | Effet |
|---|---|
| Clic | Sélectionne la caméra. **Ne déplace pas la tête de lecture** |
| Double-clic | Renomme la caméra |
| Glisser la poignée rouge | Déplace le début de la caméra sélectionnée |
| Clic droit | Menu : amener la voiture ici, ajouter une caméra ici, supprimer celle-ci |

**Sélectionner ne déplace pas le replay, et aucun modificateur ne le fait.**
Un état antérieur faisait l'inverse — clic = sélectionner *et* amener la
voiture, Maj+clic pour s'en abstenir — et les deux moitiés étaient fausses.
Déplacer le replay à chaque sélection gêne la création de caméras : choisir
une caméra à éditer n'est pas demander à aller la regarder, et l'instant qu'on
regardait ne revient pas. Et un modificateur qui désactive un comportement
n'est connu que de son auteur : rien à l'écran ne peut dire que Maj existait.

**Le double-clic garde partout le même sens : éditer le texte de l'élément.**
Sur un champ de valeur on tape la valeur, sur un segment on tape le nom.
C'est la convention universelle, du gestionnaire de fichiers aux calques de
Photoshop. « Amener la tête de lecture au début d'une caméra » est couvert
deux fois par ailleurs — Haut/Bas au clavier, et le menu du clic droit, qui a
l'avantage d'être libellé en toutes lettres.

**Les losanges ne se déplacent pas au ruban.** Un losange fait quatre pixels
sur une surface qu'on clique aussi pour sélectionner : un clic manqué de peu
déplacerait un keyframe, et un keyframe déplacé par mégarde ne se remarque
qu'au montage. Le champ `KEYFRAME` les déplace, là où le geste ne peut se
confondre avec rien.

### Clavier

Les flèches déplacent la tête de lecture, comme les touches de saut d'un point
de montage à l'autre dans Premiere ou Resolve : Gauche/Droite d'un keyframe à
l'autre, Haut/Bas d'une caméra à l'autre. Elles **s'arrêtent aux extrémités** :
boucler ferait repartir un tour en arrière sous une touche maintenue.

### La carte

La carte suit la règle du ruban : **un clic sélectionne, rien de plus**. Elle
doit dire la même chose que le ruban ou aucune des deux ne peut être crue.

### Ce que rien de tout ça n'est

Déplacer la tête de lecture **n'est pas une modification de données** : aucune
entrée d'annulation, jamais. Un glissé qui traverse la moitié du tour laisse
la pile d'annulation exactement où elle était.

## Ce qui n'a pas sa place dans l'UI

- **Aucune note de chantier.** « Pas encore implémenté », listes de ce qui manque par rapport à CamTool 2 : cela va dans les issues GitHub ou le README, jamais dans la fenêtre.
- Pas de message d'erreur technique destiné au développeur : log côté technique, message court côté utilisateur.

## Conventions visuelles acquises

- Colonnes Camera (violet) / Transform (vert) / Tracking (orange) : couleur en accent d'en-tête et teinte légère du champ, pas en aplat saturé.
- Bandeau des caméras : rouge = caméra en cours d'édition, pâle = caméra active à l'écran.
- Paramètre inactif : grisé, valeur remplacée par `--`.
- Les trois colonnes sont alignées ligne à ligne (table ImGui), largeurs égales.
- Carte : toutes les caméras visibles, l'active mise en évidence.
