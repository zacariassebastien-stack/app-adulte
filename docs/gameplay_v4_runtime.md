# Runtime V4

V4 est la seule source fonctionnelle du parcours réseau. Le catalogue actif,
ses occurrences matérialisées et le profil V4 alimentent directement le
contrôleur. Les tests multiround chargent désormais `cards.v4.fr.json`.

## Configuration réseau d'une partie

Le créateur choisit explicitement `presentiel`, `distance` ou `hybrid`. Les
deux premiers modes sont immuables. Le mode hybride peut changer son
orientation uniquement à la frontière entre deux tours, après la clôture de
l'action et avant le refill. Chaque joueur saisit son propre nombre entier de
vêtements (zéro signifie nu) et choisit les accessoires de son profil réellement
disponibles. Les accessoires ajoutés temporairement sont conservés dans la
session réseau et ne modifient pas le profil.

Une action vestimentaire publie les joueurs concernés puis reste ouverte tant
que chacun n'a pas resynchronisé son nombre réel de vêtements. Aucune déduction
théorique depuis la carte ne remplace cette saisie.

## Projection publique de l'action

À la résolution, une projection persistante partage la carte, la variante, la
direction effective, les cibles, la zone, l'accessoire concret, le piment
effectif, les paramètres utiles et les effets applicables. Elle exclut les PA,
les préférences et les valeurs personnelles. Cette projection est restaurée à
la reconnexion sans nouveau tirage de zone ou d'accessoire.

## Accessoires du profil

Un accessoire possède un identifiant stable, un nom, un propriétaire, un
ensemble exact de tags (`ANAL`, `VAGINAL`, `BUCCAL`, `PHALLUS`, `EXTERNE`,
`VIBRANT`), un état actif et trois préférences distinctes `FAIRE`, `RECEVOIR`,
`SOI`. Une combinaison inconnue vaut 18 PA; une exclusion reste représentée
séparément par une valeur absente. `PHALLUS` décrit un usage sur ou autour d'un
pénis/phallus.

## Tour et contexte

Un tour suit les états sélection, commit, négociation, résolution, action en
cours, puis frontière. Le contexte du tour est immuable. Une session
présentielle ou distance reste fixe. Une session hybride peut changer de
présence uniquement à la frontière, avant le recalcul du pool et le refill.

Une main contient au plus quatre cartes. Une main de une à trois cartes reste
valide. Le cycle commun se termine dès que le premier joueur ne possède plus
d’occurrence disponible. En hybride, un autre contexte encore jouable est
proposé avant la fin commune.

## Occurrences et résolution

Le cycle d’une occurrence est `POOL -> HAND -> RESERVED -> CONSUMED`. Le commit
réserve l’identifiant. L’annulation technique replace la même occurrence en
main. La résolution la passe en action engagée, et sa consommation est
idempotente. Les paramètres résolus, l’accessoire concret et le piment effectif
sont persistés avec l’occurrence et ne sont jamais retirés au reconnect.

Le tirage utilise toujours le piment de base. La jouabilité utilise le piment
effectif : `min(4, base + 1)` uniquement quand le jeu impose explicitement une
zone intime. Une zone choisie librement n’ajoute rien.

Après la résolution définitive, l’action est affichée comme action en cours.
Le premier appui sur **Terminé** clôt l’action pour les deux appareils. Le
signal d’apprentissage est enregistré une fois lors de la validation
définitive ; **Terminé** n’enregistre aucun signal supplémentaire.

## PA, vêtements, effets et accessoires

Pour plusieurs composantes personnelles, le PA final est la moitié du PA le
plus élevé plus la moitié de la moyenne des autres, arrondie à l’entier. Une
composante exclue interdit la combinaison. Une action mutuelle évalue les
composantes FAIRE et RECEVOIR du profil du joueur concerné.

L’état vestimentaire est un entier positif ou nul. Zéro signifie nu, sans état
intermédiaire déduit. Les retraits sont cumulatifs et bornés à zéro. Après une
action vestimentaire, le nombre réel déclaré par chaque joueur concerné devient
la nouvelle source de vérité.

Une durée vaut trois **actions suivantes**. À la clôture, les effets déjà
actifs sont décrémentés avant l’ajout ou le renouvellement de l’effet courant.
L’identité est la paire carte/cible ; deux cibles restent indépendantes.

Le pool d’accessoires de session réunit les objets normalement actifs des deux
profils, moins les désactivations temporaires, plus les ajouts temporaires. Les
tags requis sont cumulatifs sur un même objet. La sélection parmi les objets
compatibles est uniforme et ne lit aucun PA. Une préférence inconnue pour un
ensemble exact de tags vaut 18 ; une exclusion reste distincte.

## Reconnexion et continuation

La sauvegarde privée conserve mains, réservation, paramètres, piment effectif,
vêtements, pool d’accessoires, accessoires temporaires, effets et progression.
Continuer un cycle remet seulement le stock d’occurrences à disposition : les
vêtements, accessoires, contexte, effets et niveau débloqué restent inchangés.
Une nouvelle partie personnalisée recrée le setup temporaire et repart au
niveau de piment 1.
