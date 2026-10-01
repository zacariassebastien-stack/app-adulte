# Validation manuelle V3 sur deux émulateurs

Exécuter ces séquences séparément. En cas d’échec, relever l’heure, le numéro
du tour, l’écran de A et B et les lignes contenant `ROUND_` dans les logs.

## 1. Catalogue et reprise

1. A crée une partie; B la rejoint.
2. A et B lancent le duel et vérifient quatre cartes chacun.
3. Fermer complètement A, puis rouvrir l’app.
4. Vérifier que A reprend le même tour, la même main et les mêmes PA.

## 2. Duel et confidentialité

1. A et B choisissent une carte sans montrer leur écran.
2. Valider d’abord A: B ne doit voir ni carte ni valeur de A.
3. Valider B et vérifier que la valeur haute gagne.
4. Vérifier que l’écart affiché correspond aux deux valeurs figées.

## 3. Négociation

1. Le perdant propose une inversion, une enchère ou les deux.
2. Le gagnant répond séparément aux deux éléments.
3. Le perdant adapte une fois; le gagnant valide.
4. Vérifier le gagnant final, les cartes retenues et une seule dépense par coût.

## 4. Récupération

1. Avec une fixture, placer A à 10 PA et B au-dessus de 10.
2. A choisit une carte; B refuse: aucun PA ne change.
3. Refaire puis accepter; noter la valeur personnelle de A.
4. Vérifier un gain `ceil(valeur × 1,5)`, y compris au-delà de 100 PA.

## 5. Hybride

1. Démarrer une session hybride et mémoriser les deux mains.
2. Basculer l’orientation face à face vers distance.
3. Vérifier que mains et PA n’ont pas changé.
4. Jouer un tour et vérifier que seule la prochaine pioche suit l’orientation.

## 6. Apprentissage privé

1. A verrouille puis joue une carte; terminer le round.
2. Relancer A et reprendre la session.
3. Vérifier dans les données locales de test une exposition, un jeu et un
   verrou uniques, sans doublon après relance.
4. Vérifier sur B qu’aucune statistique ni préférence de A n’est visible.

## 7. Passage de round

1. Remplir le formulaire de négociation au tour N.
2. Les deux joueurs terminent puis demandent le tour suivant.
3. Vérifier tour N+1 sur A et B.
4. Vérifier formulaire vide, quatre cartes et PA conservés.
