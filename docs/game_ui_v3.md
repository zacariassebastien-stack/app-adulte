# Interface de jeu V3

## État 1

La main au repos affiche quatre cartes en éventail en bas de l’écran. Le coin
portant la valeur PA reste lisible. Une carte verrouillée remplace cette valeur
par un cadenas. Un tap ou un glissement avec suivi immédiat ouvre l’État 2.

## État 2

La carte focalisée remonte, grandit légèrement et se rapproche du centre. Les
autres cartes s’écartent sans assombrissement ni flou. Un tap sur la même carte
ouvre l’État 3; un tap sur une autre transfère directement le focus. Un swipe
vers le haut engage la carte. Un appui long verrouille, transfère ou retire
l’unique verrou.

Une tentative de jouer une carte verrouillée affiche un grand cadenas pendant
environ une seconde, puis remet la main au repos sans envoyer de commande.

## État 3

La carte ouverte est droite, entièrement visible et conserve son ratio dans
90 % de l’espace disponible. La vue est modale, sans assombrissement du reste de
l’écran. Un swipe vers le bas revient directement à l’État 1. Un swipe vers le
haut engage la carte.

## Gestes

Un déplacement minimal sépare le tap du drag. Le drag suit la dernière carte
sous le doigt sans attendre la fin d’une animation. Sortir de la zone de main
sans jouer remet la main au repos. Les animations courtes sont recalculées à
chaque changement de focus.

## Waiting

La carte engagée reste visible pendant l’attente. Un tap alterne recto et verso
pour préserver le choix lorsque les joueurs sont côte à côte. L’annulation par
swipe bas n’est activée que tant que le protocole considère encore le choix
annulable. Dès que le commit réseau est enregistré, elle est désactivée afin de
préserver commit/reveal et l’idempotence.

## HUD

Le HUD affiche uniquement les PA du joueur sous forme de texte rempli, le
message d’état, le tour, les piments actifs, l’orientation hybride et les
réglages. Les PA du partenaire ne sont jamais affichés. En État 3, seuls les PA,
le message et les réglages restent visibles. Le changement d’orientation utilise
un retournement court et n’altère pas les règles de tirage.

## Défausse

La pile apparaît uniquement pendant une phase calme et ouvre un écran complet.
La grille présente trois cartes par ligne, de la plus récente à la plus ancienne,
sans distinguer leur propriétaire. Le zoom utilise le même renderer en lecture
seule, masque la valeur personnelle et interdit jeu, verrouillage ou enchère.
