# Génération et progression piment V4

Le générateur V4 utilise les variantes du catalogue comme unités du pool. Il
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

L'unité de consommation est la variante, ou le stade, identifié par son
`variantId`. Jouer définitivement une occurrence consomme cette variante. La
simple distribution et le verrouillage ne la consomment pas. La consommation
est idempotente.

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

L'état persistant privé contient les stocks initiaux, les `variantId` consommés
et le niveau débloqué. Une reconnexion restaure donc la progression sans
rejouer une consommation et sans exposer ces données au partenaire.
