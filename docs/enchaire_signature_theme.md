# ENCHAIRE Signature V1

`enchaire_signature_v1` traduit la carte de référence validée en système de
rendu réutilisable. L'image sert de direction artistique ; elle n'est jamais
rasterisée comme fond de carte.

## Palette

| Usage | Couleur |
| --- | --- |
| Noir profond | `#0D0C0E` |
| Anthracite chaud | `#191316` |
| Panneau translucide | `#110F12` à 90 % |
| Blanc cassé | `#FFF7F2` |
| Texte secondaire | `#EDE4E0` |
| Rose corail signature | `#FF3F70` |
| Bord externe | `#FF527A` |
| Bord interne | `#F7A0B4` |
| Séparateur chaud | `#8C6E76` |

Le fond utilise un dégradé très faible et un semis vectoriel de points à
2,2 % d'opacité. Il n'ajoute aucun asset raster et reste peu coûteux.

## Typographies

Le titre et l'identité du verso utilisent la serif système `Georgia`, avec
`Noto Serif` puis la serif générique en fallback. Les labels et le texte
courant utilisent `Segoe UI`, avec `Roboto` puis la sans-serif générique en
fallback. Les labels sont en capitales, semi-gras et fortement espacés. Aucun
téléchargement de police n'a lieu à l'exécution et aucun fichier propriétaire
n'est redistribué.

## Cadre et panneaux

Le cadre externe corail mesure 3 unités, le cadre interne rose clair 1,15,
avec un intervalle de 9 et un rayon de 28. Le glow de rayon 12 reste limité par
une intensité de 0,45 et une opacité de 0,28. Les panneaux ont un fond presque
noir, une bordure chaude de 0,8, un rayon de 11 et une ombre courte.

Le layout place une illustration dominante en haut à gauche, trois panneaux
fonctionnels à droite, un titre serif centré, puis les panneaux ACTION et
PRÉCISIONS. Toutes les coordonnées sont relatives et restent éditables.

## Valeurs PA

Une carte réversible affiche la PA de sa direction active en grand et la PA de
la direction opposée en plus petit dans les états développés. L'état compact
conserve uniquement la valeur active. Une carte MUTUELLE n'affiche jamais de
ligne inverse.

## Verso

Le verso garde beaucoup d'espace négatif. Le nom ENCHAIRE est composé en serif
avec un accent corail central, suivi de « En chair et en cartes. ». Deux
ornements vectoriels fins encadrent l'identité. Le pseudo reste centré en bas,
en capitales espacées.

## Dérivation

Dupliquer le pack dans le Card Editor, puis modifier le `CardSkin` pour la
palette et les effets et le `CardLayout` pour la géométrie. Les illustrations
restent indépendantes du thème et conservent leur crop par point focal.
