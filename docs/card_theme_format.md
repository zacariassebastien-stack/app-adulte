# Format des thèmes de cartes

Le format courant porte `schema_version: 1`. Le thème système se trouve dans `assets/card_themes/classic_v1/` :

- `theme.json` décrit le `CardThemePack` ;
- `layout.json` décrit le recto et le verso ;
- `skin.json` décrit les styles ;
- `illustrations.json` référence les illustrations, sans embarquer les fichiers binaires.

## CardLayout

Un layout possède un ID stable, un nom, une version, un ratio et deux listes de blocs (`front` et `back`). Chaque bloc définit :

- `id` et `type` ;
- `box` avec `x`, `y`, `width`, `height` relatifs ;
- `alignment`, `rotation`, `padding`, `margin` ;
- `visible` et `z_index`.

Les types couvrent titre, accroche, illustration, PA, piment, direction, zones, action, détails, décoration et éléments du verso.

## CardSkin

Un skin contient les couleurs de fond, bordure, panneaux, recto et verso, l’épaisseur, le rayon, l’ombre, le glow, les styles de texte et les références de décorations. Il ne contient aucune condition métier.

## CardThemePack

Le pack associe `layout_id`, `skin_id` et un éventuel `illustration_style_id`. Il contient une version, une version minimale du renderer, une carte de preview facultative et des métadonnées préparant une activation premium future. Aucun mécanisme de boutique n’est présent.

## IllustrationAsset

Une entrée associe `illustration_id`, `card_id`, `style_id`, `asset_path`, un point de focus relatif et une safe area facultative. Le style `default` sert de fallback.

## Export et import

L’éditeur exporte un manifeste JSON autonome dans le presse-papiers. Il contient le pack, le layout, le skin et les références d’illustrations. L’import vérifie la version de schéma, les liens pack/layout/skin, les coordonnées, les tailles, les IDs et les collisions. Une collision n’est jamais remplacée silencieusement.

Les assets binaires restent des fichiers versionnés dans le projet. Un manifeste importé qui référence un asset absent est signalé par le placeholder au rendu et doit être corrigé avant distribution.
