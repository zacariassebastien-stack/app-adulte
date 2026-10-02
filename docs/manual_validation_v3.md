# Validation manuelle du parcours réseau V3

Installer la même build sur les deux appareils. Exécuter chaque séquence
séparément. En cas d’échec, relever l’heure, le tour, la phase affichée sur A
et B et les lignes `ROUND_` des logs. Ne jamais relever nonce, jeton ou valeur
privée non révélée.

## 1. Duel et reprise du secret

1. A crée une partie, B la rejoint, puis chacun choisit une carte.
2. Après la validation de A seulement, vérifier que B ne voit ni carte ni note.
3. Fermer A, le relancer et vérifier la reprise au même tour avec la même main.
4. Valider B et vérifier le résultat initial et l’écart figé.

## 2. Négociation ABA complète

1. Le perdant B propose une inversion et deux cartes, avec quelques PA.
2. Le gagnant A accepte l’inversion et refuse l’enchère.
3. B adapte une seule fois : les cartes et PA refusés ne doivent plus pouvoir
   être conservés.
4. A valide. Vérifier un débit unique, le gagnant final et l’absence de second
   tour de négociation.

## 3. Refus final et idempotence

1. Refaire une proposition acceptée par A, puis une adaptation de B.
2. A choisit « Conserver le résultat initial ».
3. Vérifier que A gagne et paie exactement l’écart initial.
4. Fermer et relancer les deux apps : PA et résultat doivent être identiques.

## 4. Compromis multi-cartes et directions

1. B propose une inversion et au moins deux cartes d’enchère.
2. Tout accepter puis valider.
3. Vérifier que la carte initiale seule change de direction.
4. Vérifier que chaque carte d’enchère conserve sa direction native et apparaît
   une seule fois dans le compromis sur A et B.

## 5. Enchère avec PA faibles

1. Avec une fixture, placer B sous 10 PA.
2. Vérifier que B ne peut pas engager de PA directs.
3. Ajouter une carte d’enchère et terminer ABA.
4. Vérifier que l’occurrence est consommée une seule fois après reconnexion.

## 6. Hybride

1. Noter les quatre cartes des deux mains puis basculer l’orientation avec
   l’icône de l’en-tête.
2. Vérifier sur A et B la même orientation, sans changement de main ni de PA.
3. Terminer un tour et vérifier que seule la prochaine pioche utilise le deck
   de la nouvelle orientation.
4. Fermer et relancer : orientation, mains et decks restants doivent reprendre.

## 7. Épuisement et mode Infini

1. Avec une fixture courte, épuiser le cycle et vérifier le message de fin de
   cycle et, s’il existe, le message neutre de répartition ajustée.
2. Choisir la continuation plus épicée et vérifier que PA, profil, historique
   et session sont conservés.
3. Au cycle suivant, activer le mode Infini.
4. Vérifier que le cycle suivant est reconstruit automatiquement sans nouvelle
   question et sans répétition immédiate dominante.

## 8. Recovery répétée

1. Avec une fixture, placer A à 10 PA. A propose une carte et B accepte.
2. A marque l’action réalisée et vérifie `ceil(valeur × 1,5)`.
3. Si A reste à 10 PA ou moins, proposer une seconde carte et l’accepter.
4. Choisir ensuite de sortir de Recovery et vérifier la reprise normale, sans
   double gain après relance.

## 9. Apprentissage et confidentialité

1. Jouer un compromis avec carte initiale inversée et deux cartes d’enchère,
   puis une Recovery acceptée.
2. Vérifier dans les données locales de A un seul apprentissage du round, avec
   chaque carte du compromis, les rôles effectifs et la Recovery.
3. Vérifier sur B qu’aucun score, préférence ou choix de profil de A n’apparaît.
4. À la première fin de cycle, choisir l’une des trois options de profil,
   relancer puis vérifier que le choix privé est mémorisé et modifiable.

## 10. `cardId` et `occurrenceId`

1. Utiliser une fixture contenant deux copies du même contenu et verrouiller la
   première occurrence.
2. Jouer la seconde occurrence et vérifier que la première reste verrouillée
   dans la main.
3. Fermer puis relancer l’app et vérifier les deux identités, le verrou et les
   zones sans duplication.
4. Engager ensuite une seule copie dans une enchère et vérifier que seule cette
   occurrence est consommée.

## 11. Profil privé modifiable

1. Ouvrir l’icône « Profil privé » pendant la partie et changer le choix
   post-partie.
2. Choisir « Personnaliser » et modifier une préférence déjà rencontrée.
3. Vérifier que seule cette ligne devient manuelle et que les autres valeurs et
   observations sont conservées.
4. Relancer l’app et vérifier la persistance locale, sans changement visible
   sur l’appareil partenaire.
