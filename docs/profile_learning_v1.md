# Moteur d’apprentissage de profil V1

## Frontière et confidentialité

Le moteur est local, incrémental et sans apprentissage automatique. Il reçoit des faits déjà résolus par les moteurs de jeu. Il ne décide ni du duel, ni du consentement, ni de l’éligibilité d’une carte. Son état reste dans `profile_learning_states`, indexé par le profil local, et ne fait partie d’aucune projection publique réseau.

Une entrée n’est créée que lorsqu’une préférence ou une combinaison est rencontrée. Aucune combinaison cartésienne n’est préconstruite. Une exclusion est ignorée par l’apprentissage et ne peut être levée que par une personnalisation manuelle.

## Sources et amorçage

Le swipe initialise `J’adore` à 3 PA, `Ça me plaît` à 8 PA, `Je ne sais pas` à 20 PA et `Exclu` sans score. Les sources sérialisées sont `INITIAL_SWIPE`, `AUTO_LEARNED` et `MANUAL_CUSTOMIZED`. Après la première partie, le choix `personnaliser`, `faire confiance au jeu` ou `différer` est modifiable sans effacer les preuves.

## Clé et signaux

La clé sparse associe une préférence à un rôle (`general`, `faire`, `recevoir`, `mutuel`, `solo`, `simultane`) et, si nécessaire, à une zone. Les directions spécialisent une préférence et ne sont jamais notées seules. Avec une zone, la combinaison action-zone reçoit le poids principal et l’action générale une preuve secondaire réduite.

Les événements acceptés sont :

- état de main réellement disponible : exposition, carte jouée, verrouillée ou ignorée ;
- résultat final accepté : carte gagnante et cartes uniques du compromis final ;
- résistance explicite : modification recherchée, inversion, défense finale ou évitement cohérent.

Une carte ignorée n’ajoute aucune résistance. Un STOP ou un résultat non accepté n’ajoute aucune preuve. Pour une action dirigée, seuls les rôles finaux alimentent `FAIRE` et `RECEVOIR`, y compris après inversion.

Une carte conceptuelle réversible ne fusionne jamais ses deux estimations :
`FAIRE` et `RECEVOIR` restent deux clés d'apprentissage privées. L'occurrence
conserve sa direction native, mais la résolution crédite uniquement sa
direction effective. Ainsi une occurrence tirée RECEVOIR puis officiellement
inversée nourrit FAIRE, sans ajouter de preuve RECEVOIR.

## Calcul

La fenêtre principale conserve les 20 dernières observations pertinentes par clé, avec les cumuls historiques en parallèle.

```text
attractionRelative = attraction / exposition
acceptanceRelative = acceptance / resultOccurrences
resistanceRelative = resistance / resultOccurrences

tendance = 0.5 × attractionRelative
         + 0.5 × acceptanceRelative
         - resistanceRelative
```

Une division sans observation vaut zéro. Les amplitudes sont : très positive `-1 PA`, positive `-0,5`, stable `0`, résistance notable `+0,5`, résistance forte `+1`. Seul le mouvement vers un PA plus faible est multiplié par le piment moyen : `×0,4`, `×0,6`, `×0,8` ou `×1`.

Un tag principal vaut `1`, un secondaire `0,5`, deux préférences principales indissociables `0,75` chacune. Contexte, technique, matériel et requirements valent zéro.

## Propositions

Une proposition exige un franchissement de catégorie, 10 occurrences équivalentes et 3 occurrences de confirmation. Une source personnalisée manuellement exige au moins 20 nouvelles occurrences. Un refus conserve les données et impose 20 nouvelles occurrences avant une proposition équivalente. La valeur 20 représente l’incertitude : une tendance cohérente peut proposer directement une catégorie détaillée.

Le moteur stocke une estimation décimale, mais ne propose rien tant qu’elle reste dans la catégorie actuelle. L’acceptation devient la nouvelle référence ; elle n’efface pas l’historique agrégé.

## Pondération hybride

Le composant pur `HybridDrawWeighting` répartit le poids sur le pool réellement éligible. En orientation distance, les groupes visent 70 % sans `DISTANCE_EXCLUE` et 30 % avec ; en orientation face à face, 30 % et 70 %. Chaque carte reçoit `part du groupe / taille du groupe`. Si un groupe est vide, le groupe restant reçoit uniformément tout le poids. Une carte `DISTANCE_EXCLUE` reste donc autorisée en hybride.
# Intégration au parcours réseau

`NetworkProfileLearningCoordinator` alimente le moteur existant sans créer de
seconde formule. Il enregistre localement la main réellement exposée, la carte
jouée, le verrou et la carte du résultat final accepté. Les rôles finaux sont
projetés après inversion. MUTUEL, SOLO et SIMULTANE restent distincts.

Chaque round possède un marqueur privé idempotent. La reconstruction du
contrôleur ou une notification réseau répétée ne peut donc pas doubler les
statistiques. Aucune entrée d’apprentissage, proposition ou exclusion n’entre
dans les DTO publics.
