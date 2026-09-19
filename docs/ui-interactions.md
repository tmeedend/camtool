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
| Échap pendant un glissé ou une saisie | annule, restaure la valeur d'avant |
| Ctrl maintenu | pas ÷ 4 |
| Shift maintenu | pas × 4 |

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

1. **Une infobulle par élément.** Elle dit d'abord **ce que fait le paramètre**, en une phrase, puis les gestes utiles. Priorité aux noms cryptiques : `STRENGTH LO.`, `STRENGTH RO.`, `OFF TRACKING`, `STR PITCH`, `STR HEADING`, `MIX`, `AF`.
2. **Un délai avant affichage** (ImGui : `ImGuiHoveredFlags_DelayNormal`). Avec 21 champs serrés, sans délai les bulles clignotent en permanence.
3. **Une ligne de statut contextuelle**, une seule, en bas de la fenêtre : décrit ce qui est sous le curseur. Toujours visible, donc découvrable — contrairement à une infobulle, qu'il faut savoir aller chercher.
4. **Un bouton `?`** affichant la légende complète (losanges, code couleur du bandeau, raccourcis). Seul endroit où l'aide est exhaustive.

Les noms de fonctions varient selon le binding Lua de CSP : vérifier dans le SDK avant de reprendre les noms C++ cités ici.

## Ce qui n'a pas sa place dans l'UI

- **Aucune note de chantier.** « Pas encore implémenté », listes de ce qui manque par rapport à CamTool 2 : cela va dans les issues GitHub ou le README, jamais dans la fenêtre.
- Pas de message d'erreur technique destiné au développeur : log côté technique, message court côté utilisateur.

## Conventions visuelles acquises

- Colonnes Camera (violet) / Transform (vert) / Tracking (orange) : couleur en accent d'en-tête et teinte légère du champ, pas en aplat saturé.
- Bandeau des caméras : rouge = caméra en cours d'édition, pâle = caméra active à l'écran.
- Paramètre inactif : grisé, valeur remplacée par `--`.
- Les trois colonnes sont alignées ligne à ligne (table ImGui), largeurs égales.
- Carte : toutes les caméras visibles, l'active mise en évidence.
