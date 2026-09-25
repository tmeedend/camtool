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

**Ce qui est écrit sur un segment : son numéro, et rien d'autre.** Le nom va
dans la ligne de statut, au survol.

Ce n'est pas ce qui était fait, et l'ancienne règle est la raison du
changement : le nom s'il tenait, sinon le numéro s'il tenait, sinon rien — sauf
celui sous le curseur, écrit au-dessus du ruban. Trois états pour la même
étiquette, et rien à l'écran pour dire dans lequel on est. *« Ce n'est pas
clair de parfois afficher un numéro, parfois le nom »* — Théo, et il a raison :
un libellé qui change de nature selon la place disponible ne se lit pas, il se
devine.

Le numéro seul est le bon choix pour la surface, parce que c'est lui qui rend
un set **dénombrable** : il est court, il tient presque toujours, et il est le
même d'un segment à l'autre. Le nom est plus long, plus utile, et a un endroit
fait pour lui qui ne manque jamais de place — la ligne de statut, seul canal
d'aide depuis que les infobulles sont parties.

**Un segment trop fin même pour un chiffre reste vide, et c'est sans
conséquence** : il est toujours parfaitement visible — sa teinte et son trait
de relais sont dessinés quelle que soit sa largeur — et le survoler le nomme.
Ce qui disparaît, c'est l'écriture au-dessus du ruban, qui était le troisième
état et occupait la ligne des losanges.

**Les losanges ne se déplacent pas au ruban.** Un losange fait quatre pixels
sur une surface qu'on clique aussi pour sélectionner : un clic manqué de peu
déplacerait un keyframe, et un keyframe déplacé par mégarde ne se remarque
qu'au montage. Le champ `KEYFRAME` les déplace, là où le geste ne peut se
confondre avec rien.

### La liste `time` : le ruban le long du replay

La liste `time` pose ses caméras sur **le replay** et non sur le tour. Le
ruban couvre alors tout le replay, sa règle se lit en secondes, et les
positions du panneau aussi ; les gestes ne changent pas. Aller quelque part
place le replay directement — pas de recherche, la position est une frame.
La carte ne montre pas de caméras : un instant du replay n'est pas un lieu.

### Les caméras de stand : le bouton `pit`

Les caméras `PIT ONLY` ne jouent que voiture aux stands : ce sont une
seconde liste sur le même tour. Le ruban et la carte en montrent **une à la
fois** — le bouton `pit` passe de l'une à l'autre, et tous les gestes restent
les mêmes. Une caméra ajoutée dans la vue des stands est une caméra de stand.

**La vue suit la sélection.** Choisir une caméra de stand, ou cocher
`PIT ONLY` sur celle qu'on édite, emmène le ruban avec elle : la caméra
éditée est toujours visible. Sans ça, cocher `PIT ONLY` faisait disparaître
la caméra du ruban, et une caméra de stand ne se sélectionnait que pendant
qu'elle jouait. Tranché par Théo entre ce bouton et une seconde ligne fixe
sous le ruban.

### Clavier

**Les touches de CamTool 2 sont là, sans touche par défaut** (tranché par
Théo) : prendre la caméra — déjà tenue, charger le fichier suivant, comme
F10 —, la relâcher, et charger les fichiers 1 à 5 de la piste (Y à P). On
les affecte dans `keys`. Charger par une touche demande un second appui s'il
y a du travail non sauvé, comme le bouton.

**Les touches de caméra d'AC relâchent la caméra** — F1, F2, F3, F5, F6, F7,
la liste de CamTool 2, lues directement comme CamTool 2 les lisait.
Surveiller le mode de caméra d'AC a été essayé et ne marche pas : caméra
tenue, F1 ne change pas le mode rapporté, et la prise elle-même le change.


Les flèches déplacent la tête de lecture, comme les touches de saut d'un point
de montage à l'autre dans Premiere ou Resolve : Gauche/Droite d'un keyframe à
l'autre, Haut/Bas d'une caméra à l'autre. Elles **s'arrêtent aux extrémités** :
boucler ferait repartir un tour en arrière sous une touche maintenue.

### La carte

La carte suit la règle du ruban : **un clic sélectionne, rien de plus**. Elle
doit dire la même chose que le ruban ou aucune des deux ne peut être crue.

**Elle ne porte aucun nom écrit sur le tracé**, et c'est un choix de forme, pas
un oubli : un tracé est une courbe, un nom est un rectangle, et poser l'un sur
l'autre demande de faire tourner le texte ou de tirer un trait de rappel — deux
choses qui coûtent cher et se lisent mal sur un circuit qui se replie sur
lui-même comme Spa. La carte dit **où**, le ruban dit **qui**.

Le nom de la caméra sous le curseur va donc là où va celui du ruban : **la
ligne de statut**. Un seul endroit pour la même question, quelle que soit la
surface qu'on survole.

### Ce que rien de tout ça n'est

Déplacer la tête de lecture **n'est pas une modification de données** : aucune
entrée d'annulation, jamais. Un glissé qui traverse la moitié du tour laisse
la pile d'annulation exactement où elle était.

## Les voitures : `ACTIVE CAR` et `EXTRA CAR`

Deux lignes sans valeur à taper ni à glisser : une voiture n'est pas un
nombre qu'on règle. Seules les **flèches** marchent, et elles vont à la
voiture précédente ou suivante **sur la piste**, pas au numéro suivant —
comme dans CamTool 2, parce qu'on remonte un peloton, pas une liste.

- `ACTIVE CAR` est la voiture que le replay suit : ses flèches **déplacent le
  replay** sur une autre voiture.
- `EXTRA CAR` est celle vers laquelle `MIX` fait pivoter la visée. Elle part
  de **aucune** (`--`), et y revient quand les flèches repassent sur la
  voiture active : c'est le seul chemin vers « pas d'extra car », et c'est là
  que la marche tombe d'elle-même. Tranché par Théo : partir de la voiture 0,
  comme CamTool 2, faisait que `MIX` ne produisait rien sans dire pourquoi.
- Ni l'une ni l'autre n'est enregistrée dans le fichier, ni n'entre dans la
  pile d'annulation : c'est de l'état de session, comme dans CamTool 2.

## Enregistrer un chemin : un bouton qui dit ce qu'il fera

Les trois chemins — celui d'une caméra, le tour de piste, la voie des stands —
s'enregistrent chacun avec **un seul bouton** dont le libellé annonce la
suite : `Record`, puis `Stop` pendant l'enregistrement, puis `Remove` une fois
qu'il existe. C'est le bouton tri-état de CamTool 2. `Record path` est à côté
du titre `SPLINE` (il concerne la caméra choisie) ; les chemins de piste et
de stand, qui concernent le fichier, sont dans `keys` avec les autres
réglages. Un enregistrement entier est **une** entrée d'annulation : on
annule une prise, pas quarante points.

## Mouse look : Alt

Le geste de CamTool 2 pour **reprendre la caméra à la main** : Alt maintenu,
elle est à la souris ; Alt relâché, le fichier la reprend.

- **Clic gauche + mouvement** tourne la caméra. Pas au mouvement brut : à
  l'écart entre le pointeur et la moyenne de ses positions de la dernière
  seconde. Un geste bref continue donc de tourner un instant, et relâcher le
  bouton laisse la caméra finir sur son élan. C'est ce qui rend un
  panoramique à la main utilisable à l'image — la raison d'être du geste.
- **Shift / Ctrl**, seulement Alt tenu, zooment et dézooment, avec une montée
  et une descente douces. Hors d'Alt ils gardent leur sens de ×4 / ÷4 sur les
  valeurs : les deux usages ne se chevauchent jamais.
- **Caméra tenue** : la lecture cède la main en une seconde et la reprend en
  deux ; la position reste figée, seule la visée et l'optique changent.
  **Caméra libre d'AC** : c'est elle qui est orientée, pour viser un plan
  avant d'épingler ses valeurs.
- **Un clic sur une fenêtre reste à la fenêtre**, Alt tenu ou non. Tranché
  par Théo : dans CamTool 2, Alt + clic sur un champ faisait aussi tourner la
  caméra.
- Les trois touches se réaffectent comme les autres raccourcis ; ce sont les
  seules à avoir une touche par défaut, celles de CamTool 2.

## Ce qui détruit du travail demande deux fois

Deux gestes effacent ce qui n'est pas sauvé : **Reset**, qui vide la liste de
caméras, et **charger un fichier**, qui remplace tout le document et vide la
pile d'annulation. Les deux demandent confirmation, de la même façon.

| | Premier clic | Second clic |
|---|---|---|
| Reset | le bouton devient `Reset?` | il vide la liste — et `Undo` la ramène |
| Nom de fichier | le bouton devient `lose changes? <nom>` | il charge, et la pile part avec |

**L'état armé se lit sur le bouton, pas seulement dans la ligne de statut.**
Avertir uniquement en bas de la fenêtre met l'avertissement loin de ce qu'on
vient de cliquer, et le premier clic se lit alors comme « il ne s'est rien
passé ». Reset l'a appris le premier.

**Charger ne demande que s'il y a quelque chose à perdre** — le même signal que
l'étoile de `Save *`, donc l'avertissement apparaît exactement quand l'étoile
est là et les deux ne peuvent pas se contredire. Poser la question à chaque
fois est la façon de la transformer en réflexe et de la faire cesser d'être lue.

**N'importe quelle autre action annule la question.** Pas n'importe quel
mouvement : survoler le ruban n'est pas une décision, et c'est le chemin que
la souris prend pour revenir au bouton.

## Ce qui n'a pas sa place dans l'UI

- **Aucune note de chantier.** « Pas encore implémenté », listes de ce qui manque par rapport à CamTool 2 : cela va dans les issues GitHub ou le README, jamais dans la fenêtre.
- Pas de message d'erreur technique destiné au développeur : log côté technique, message court côté utilisateur.

## Conventions visuelles acquises

- Colonnes Camera (violet) / Transform (vert) / Tracking (orange) : couleur en accent d'en-tête et teinte légère du champ, pas en aplat saturé.
- Bandeau des caméras : rouge = caméra en cours d'édition, pâle = caméra active à l'écran.
- Paramètre inactif : grisé, valeur remplacée par `--`.
- Les trois colonnes sont alignées ligne à ligne (table ImGui), largeurs égales.
- Carte : toutes les caméras visibles, l'active mise en évidence.
