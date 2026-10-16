# Génération et progression piment V4

Le générateur V4 utilise les occurrences matérialisées des variantes comme
unités du pool. Il
reste dans le sous-système de deck existant : les cartes en main, engagées,
défaussées ou épuisées continuent d'utiliser le lifecycle normal du jeu.

## Pondérations par style

| Style | 🌶️1 | 🌶️2 | 🌶️3 | 🌶️4 |
|---|---:|---:|---:|---:|
| Soft | 45 % | 40 % | 13 % | 2 % |
| Épicé | 20 % | 40 % | 30 % | 10 % |
| Intenable | 10 % | 25 % | 40 % | 25 % |

Ces valeurs sont des poids de tirage, pas des quotas par main. Le RNG est
injectable afin de rendre les tests reproductibles.

Une main normale contient quatre cartes. Le générateur garantit, lorsque le
pool le permet, au moins une 🌶️1/2 en Soft, une 🌶️2/3 en Épicé, ou une 🌶️3/4
en Intenable. La garantie occupe un emplacement normal. Si aucune variante
restante ne peut la satisfaire, le remplissage continue sans boucle de reroll.
Une carte déjà conservée dans la main, notamment verrouillée, n'est pas
remplacée.

Après la garantie du style, le remplissage privilégie aussi une variante déjà
jouable si la main n'en contient aucune et si le pool en propose une. Ce
garde-fou évite une main bloquée sans filtrer les variantes plus fortes.

## Distribution et jouabilité

Le tirage ne filtre pas le pool avec la progression. Une carte 🌶️4 peut donc
être distribuée et verrouillée lorsque seul 🌶️1 est jouable. La progression
commence à 🌶️1 et autorise tous les niveaux inférieurs ou égaux au niveau
débloqué. Les déblocages 1 → 2 → 3 → 4 sont irréversibles.

Avant la résolution de paramètres dynamiques, le générateur emploie le piment
catalogue de la variante. Après résolution d'une occurrence, toute décision
qui dépend de son intensité utilise l'API canonique `v4EffectiveChiliLevel`
(`min(4, base + modificateur de zone)`). Le générateur ne suppose jamais une
zone qui n'a pas encore été choisie.

## Progression du pool

Pour chaque niveau `n` :

```text
pourcentage restant(n) = unités non consommées(n) / unités initiales(n)
```

Le niveau suivant est débloqué lorsque le pourcentage restant du niveau actif
est strictement inférieur à celui du niveau suivant. Les fractions sont
comparées exactement, sans arrondi. Après chaque consommation, le moteur
répète la comparaison pour autoriser plusieurs déblocages cohérents. Un niveau
absent ne provoque aucune division par zéro : un niveau actif sans unité ne
bloque pas le suivant, tandis qu'un niveau suivant absent n'est pas débloqué.

L'unité de consommation est l'occurrence, identifiée par son `occurrenceId`.
Une variante ou un stade possède une occurrence par défaut, mais une
métadonnée de multiplicité peut en matérialiser plusieurs. Jouer définitivement
une occurrence ne consomme jamais ses copies. La simple distribution et le
verrouillage ne consomment rien. La consommation est idempotente.

La progression compare toujours le **pool global** : toutes les occurrences
du cycle moins les occurrences consommées. Le **pool actif** est une projection
temporaire de ce pool selon la présence courante, les accessoires disponibles,
les exclusions privées et le stade séquentiel. Un changement de contexte ne
modifie donc aucun stock de progression et ne peut pas débloquer un niveau.

## Présence et mode hybride

La métadonnée canonique `presence` vaut `PRESENTIEL`, `DISTANCE` ou `BOTH`.
Une session hybride possède un état courant présentiel ou distance choisi par
les joueurs. Le changement recalcule le pool actif : une occurrence
temporairement incompatible en sort puis y revient lorsque le contexte redevient
compatible. Une occurrence consommée ne revient jamais. Une carte déjà en main
reste visible et verrouillable, mais sa jouabilité est refusée tant que sa
présence est incompatible.

Classification V4 actuelle :

- `BOTH` : 018, 021, 032, 033, 038, 039, 042–048, 050, 052–054, 056–058,
  060–061 ;
- `PRESENTIEL` : 001–017, 019–020, 022–031, 034–037, 040–041, 049, 055,
  051, 055, 059, 062–065 ;
- `DISTANCE` uniquement : aucune carte actuelle.

Les cartes média explicitement validées 042–047, 053 et 058 sont donc
disponibles dans les deux états. Le roleplay reste narratif et le lieu ne
filtre que lorsqu'une incompatibilité réelle est portée par une métadonnée.
Aucune carte ne change automatiquement l'état de présence.

## Accessoires et vêtements

Une liste `required_accessories_any_of` rend une occurrence active dès qu'au
moins une catégorie compatible est déclarée disponible pour la session. Un
accessoire n'a pas besoin d'être déjà utilisé. Les cartes 049–051 acceptent les
catégories sextoy, vibrant ou jouet contrôlable à distance ; 052 requiert un
jouet contrôlable à distance.

006 et 007 retirent respectivement jusqu'à un et deux vêtements du compteur
courant. Leurs occurrences s'enchaînent donc cumulativement, sans rhabillage,
et le compteur est borné à zéro. Les comportements 008–011 réinitialisent
d'abord la cible avec une tenue complète, puis appliquent leur résultat :
sous-vêtements, nudité, strip-tease ou strip-tease complet. 012 et 013 prennent
un résultat de tenue choisi et peuvent augmenter le nombre de vêtements
retirables. Le modèle volontairement simple conserve `HABILLE`,
`SOUS_VETEMENTS`, `NU` et un compteur.

Pour une capacité totale `T` de vêtements retirables au début du cycle, la
matérialisation crée `min(2, T)` occurrences de 006, puis
`ceil((T - occurrences006) / 2)` occurrences de 007. Avec deux joueurs à cinq
vêtements, cela donne deux occurrences 006 et quatre occurrences 007, soit une
capacité exacte de dix retraits. Cette règle garde deux unités fines pour les
cas impairs puis couvre le reste avec le minimum d'unités de deux retraits.

## Cartes évolutives et défausse

Chaque ligne d'évolution ne propose que son plus bas stade non consommé. Un
stade supérieur ne peut pas être tiré parce que son piment est déjà débloqué.
Après consommation du stade 1, le stade 2 devient candidat, puis le stade 3.
Lorsque tous les stades sont consommés, cette ligne disparaît du pool normal.
Les variantes éditoriales distinctes d'une même carte conservent leurs lignes
d'évolution propres.

Une variante tirée est retirée des listes de pioche pour éviter une seconde
occurrence simultanée, mais reste non consommée tant qu'elle est en main. À la
fermeture du round, les occurrences engagées sont consommées puis déplacées
vers la défausse par le lifecycle existant. La défausse n'est pas recyclée
automatiquement. Un nouveau cycle explicite reste une décision distincte du
jeu ; l'épuisement normal du pool est conservé.

L'état persistant privé contient les stocks initiaux, les `occurrenceId` consommés
et le niveau débloqué. Une reconnexion restaure donc la progression sans
rejouer une consommation et sans exposer ces données au partenaire. La lecture
reste compatible avec les anciennes sauvegardes fondées sur `variantId`.

## Profil et hasard

Les PA privés 1–20 ne sont ni lus par la projection contextuelle ni utilisés
comme poids. À contraintes égales, PA 1 et PA 20 ont exactement la même chance.
Seul le veto `Exclu`, déjà appliqué par l'éligibilité de profil avant la
matérialisation, retire le contenu. Après les filtres obligatoires, seules les
pondérations piment 6A et le hasard interviennent.
