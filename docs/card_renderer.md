# Card Renderer ENCHAIRE

Le rendu d’une carte est composé sans dupliquer son contenu métier :

`CardRenderDefinition + CardLayout + CardSkin + IllustrationAsset = CardRenderer`

`CardRenderDefinition` est l’adaptateur de lecture du catalogue. Il expose l’identifiant de carte et de variante, le titre, l’action, la direction, les zones, le niveau de piment, la valeur personnelle, les précisions et l’identifiant d’illustration. Il ne contient aucune règle de duel, de consentement ou d’éligibilité.

`CardRenderer` est le widget unique utilisé dans le jeu local, le parcours réseau, les previews et l’éditeur. Le renderer conserve le ratio du layout, transforme les coordonnées relatives en contraintes locales et ne parse aucun JSON pendant `build`. Au bootstrap, les fichiers `classic_v1` sont chargés une fois dans `CardThemeRegistry`; le fallback compilé ne sert qu’à protéger le tout premier rendu et les tests isolés.

## États visuels

Les états disponibles sont `normal`, `focused`, `full`, `locked`, `selected`, `committed`, `waiting`, `discarded`, `readonly` et `hidden`.

Ils ne modifient jamais la définition métier. `hidden` affiche le verso. Au repos, `locked` remplace la valeur PA par le cadenas. En affichage `focused` ou `full`, la valeur reste visible et le cadenas peut être présenté sous celle-ci.

## Responsive

Le layout utilise exclusivement des valeurs entre 0 et 1. Le renderer choisit la plus grande carte respectant le ratio dans l’espace disponible. La taille des textes est dérivée de la largeur finale de la carte. Les tests couvrent petit téléphone, téléphone large et fenêtre tablette/desktop.

## Illustrations

Le renderer cherche d’abord `(cardId, illustrationStyleId)`, puis `(cardId, default)`. En l’absence d’asset ou si son chargement échoue, il affiche le placeholder canonique. Le skin et le layout ne contiennent aucune image propre à une carte.
