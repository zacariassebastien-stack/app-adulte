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
swipe bas est activée après l’enregistrement du commit tant que le serveur est
encore en phase `COMMIT`. Elle rend exactement l’occurrence engagée à la main.
Dès que la révélation commence, elle devient irréversible et le geste est
refusé sans altérer le choix.

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

## Réglages

Le bouton ouvre un panneau opaque sans interrompre l’écoute réseau. Il regroupe
les sons, vibrations, thème de cartes, animations, profil privé, aide et sortie
de partie. Les préférences d’affichage sont locales et persistées; couper les
animations supprime les transitions de la main et du bouton d’orientation.

Quitter demande une confirmation puis ferme définitivement la session pour les
deux joueurs. Le partenaire voit un message neutre et un retour à l’accueil.
L’historique local affiche les dix dernières parties terminées avec une date et
un profil humoristique, sans partenaire, PA, cartes ni donnée de profil privée.
