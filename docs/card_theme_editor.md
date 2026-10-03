# Card Theme Editor

Le Card Editor est un outil Windows autonome situé dans `tools/card_editor`.
Il n'est pas accessible depuis l'application mobile et ne démarre ni lobby, ni
gameplay, ni Supabase.

Le renderer compose toujours une carte à partir de quatre éléments distincts :

`CardRenderDefinition + CardLayout + CardSkin + IllustrationAsset`.

- `CardRenderDefinition` porte le contenu d'une occurrence ;
- `CardLayout` porte les positions, dimensions, alignements, marges, paddings,
  rotations, visibilité et ordre des blocs ;
- `CardSkin` porte la palette, les deux bordures, le glow, le fond, la matière,
  les panneaux et la typographie ;
- `IllustrationAsset` associe une image interchangeable et son point focal.

## Thèmes fournis

- `enchaire_signature_v1` est la référence visuelle officielle. Il est
  sélectionné au premier démarrage, modifiable et sauvegardable dans l'outil ;
- `classic_v1` reste disponible pour compatibilité et comparaison. Il faut le
  dupliquer avant modification.

L'écran permet de choisir une carte, un thème, le recto ou le verso et trois
modes de preview : carte unique, échantillon représentatif et catalogue
complet virtualisé. Le sélecteur FAIRE / RECEVOIR / MUTUEL couvre les valeurs
PA extrêmes et vérifie qu'aucune valeur inverse n'apparaît pour MUTUEL.

Les contrôles exposent les fonds, panneaux, bordures externe et interne,
épaisseurs, écart du double cadre, rayons, glow, ombres, matière, couleurs de
texte, familles typographiques, tailles et espacements. Un bloc sélectionné
peut être déplacé, redimensionné et régler son alignement, sa rotation, sa
marge, son padding et sa visibilité.

## Créer un thème dérivé

1. Sélectionner `enchaire_signature_v1`.
2. Utiliser **Dupliquer pack** pour obtenir des IDs éditables indépendants.
3. Ajuster le skin et déplacer les blocs du layout.
4. Vérifier les previews recto, verso, FAIRE, RECEVOIR et MUTUEL.
5. Vérifier l'échantillon pour les titres et textes longs, les piments 1/5,
   l'illustration absente et les PA 1/20.
6. Sauvegarder. Les quatre manifestes sont écrits dans
   `assets/card_themes/<theme_id>/`.

Les coordonnées restent relatives. Une preview réussie ne dépend donc pas de
la résolution de la fenêtre de l'éditeur.
