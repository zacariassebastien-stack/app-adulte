# Gameplay V3

## Sources de vérité

Le catalogue jouable utilise `v3_deck_enabled`, les tags `v3.*`, les
requirements V3 et `baseEngagementLevel`. Les anciennes cartes de scénario
roleplay 91–100 restent lisibles pour la migration mais ne sont jamais placées
dans le deck V3. Les moteurs de domaine restent la source des règles; l’UI ne
recalcule ni les coûts ni l’éligibilité.

## PA et duel

Chaque joueur commence à 100 PA. La valeur personnelle la plus haute remporte
le duel initial. Si ce résultat devient le compromis final, le gagnant initial
paie exactement l’écart entre les deux snapshots. Les snapshots sont immuables.
Une négociation conserve séparément `initialWinnerId` et `finalWinnerId`.

Le seuil de récupération est fixe à 10 PA, calculé depuis les 100 PA initiaux.
Il n’existe aucun plafond supérieur. Une récupération acceptée rapporte
`ceil(valeur personnelle × 1,5)`; un refus ne produit ni gain ni apprentissage.

## Tour

Le tour suit commit/reveal, résolution initiale, négociation bornée, validation
du compromis, consommation des cartes, repioche et tour suivant. La négociation
V3 est ABA: le perdant propose, le gagnant répond séparément à l’inversion et à
l’enchère, le perdant adapte une fois, puis le gagnant valide. Une inversion ne
concerne que la carte initiale et coûte la valeur haute initiale.

Les requirements filtrent la disponibilité. Seuls les tags
`v3.preference.*` sont notés et appris. Les directions spécialisent une
préférence; elles ne reçoivent jamais de score isolé.

## `cardId` et `occurrenceId`

`cardId` identifie le contenu éditorial stable. `occurrenceId` identifie un
exemplaire précis créé pour un cycle. La main, le verrouillage, l’engagement,
la défausse, la corruption, la Recovery et les cartes d’enchère manipulent
toujours l’occurrence. Deux exemplaires du même contenu peuvent donc coexister
sans que jouer le premier modifie le second.

La source de profil reste la combinaison sémantique de la carte et de son rôle:
l’occurrence empêche les doubles consommations, mais ne crée pas une nouvelle
préférence. Une édition manuelle marque uniquement la préférence modifiée
`MANUAL_CUSTOMIZED`; elle ne modifie ni les autres entrées ni les observations.
