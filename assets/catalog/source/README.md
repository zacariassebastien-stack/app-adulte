# Source utilisée par le runtime antérieur à la refonte

Le contrat éditorial actif est désormais
[`../concepts/active.fr.json`](../concepts/active.fr.json) : 56 concepts.
Voir le [contrat du Lot 1](../../../docs/catalog/concept_contract.md).

`cards.v2.fr.json` reste chargé par les anciens consommateurs tant que les
lots moteur, usage, serveur et UI ne les ont pas remplacés. Ce fichier ne
fait pas autorité sur les décisions éditoriales du nouveau catalogue.

`cards.v1.fr.json`, ancien seed sans lecteur de production ni test, a été
supprimé au Lot 1. Son empreinte dans `docs/source_hashes.json` reste une
attestation historique de l'archive initiale, pas une liste des fichiers actifs.

Les profils, tags et scénarios encore consommés restent en place : ils ne
doivent pas être supprimés avec les anciens fichiers de cartes sans examen
de leurs dépendances.
