# Deck builder V3

Le builder reçoit uniquement les variantes déjà éligibles après profil,
exclusions, requirements, piment, mode et matériel. Il construit les
occurrences du cycle puis cesse d’intervenir. Chaque pioche dans ce deck est
aléatoire et ne favorise aucune carte précise.

Pour chaque niveau, les cartes distinctes sont utilisées avant les copies. Une
même carte reste strictement sous 50 % des occurrences du niveau. Un manque est
complété par une intensité voisine: Soft cherche d’abord vers le bas; Épicé et
Intenable cherchent d’abord vers le haut. Chaque substitution conserve le
niveau demandé, le niveau utilisé et le nombre d’occurrences pour permettre un
message final neutre.

En hybride, deux decks virtuels complémentaires sont construits. L’orientation
face à face vise 70 % de cartes `DISTANCE_EXCLUE`; l’orientation distance en
vise 30 %. Changer d’orientation ne modifie ni la main, ni les PA, ni la
session. Une pioche retire une occurrence du deck actif et au plus une
occurrence identique de l’autre deck.

À l’épuisement, l’état de cycle sait représenter la montée d’intensité, le
maintien en Intenable, le mode Infini, la nouvelle partie et la fin. Les
dernières occurrences vues sont repoussées à la fin du cycle reconstruit pour
éviter une répétition immédiate.

## `cardId` et `occurrenceId`

Le builder peut répéter un `cardId`, mais matérialise chaque copie avec un
`occurrenceId` unique dans le cycle. Les deux decks hybrides utilisent les
mêmes identités lorsqu’une occurrence est commune. Une pioche retire cette
identité du deck actif et une seule identité correspondante du miroir.

Le rapport de pénurie conserve, par niveau demandé, le nombre demandé, le
nombre disponible, le manque et la répartition des intensités de remplacement.
L’interface n’affiche que les intensités et les quantités, jamais la raison
privée de l’inéligibilité.

Un cycle est terminé lorsque les deux decks ne fournissent plus d’occurrence
et que les occurrences restantes en main ont été résolues. En mode Infini, le
cycle suivant est reconstruit automatiquement à la même intensité. Sinon la
progression est Soft → Épicé → Intenable, puis reste Intenable.
