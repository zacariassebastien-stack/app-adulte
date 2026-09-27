# Passe éditoriale V2

## Changements
- Suppression des variantes « guidées » générées automatiquement sans valeur éditoriale.
- Ajout de variantes uniquement lorsqu'elles changent réellement l'action.
- Directionnalité explicite: FAIRE, RECEVOIR, MUTUAL, FAIRE_RECEVOIR, CONTEXTUAL.
- Ajout de paramètres légers quand une nouvelle carte/variante serait inutile.
- Ajout automatique de ProfileRequirement lorsqu'une variante ajoute une dimension sensible.
- Conservation des stable_id V1 pour les cartes.

## Principe pour l'extension
Une nouvelle variante doit répondre OUI à au moins une question:
1. Change-t-elle le consentement nécessaire ?
2. Change-t-elle réellement l'intensité ?
3. Change-t-elle le rôle ou la direction ?
4. Change-t-elle la mise en scène de façon significative ?
5. Change-t-elle une condition de session ou un StateEffect ?

Sinon, utiliser un paramètre, un texte alternatif ou ne rien ajouter.
