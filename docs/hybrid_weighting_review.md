# Pondération hybride existante — inspection sans modification

**Décision utilisateur appliquée au moteur pur du Lot 2 : suppression du biais
70/30 et de la duplication.** L'orientation ne sert qu'à l'admissibilité, avant
le calcul des classes. Voir [le moteur conceptuel](concept_deck_engine.md).
Les mécanismes historiques décrits ci-dessous restent encore utilisés par
l'ancien runtime ; ils ne sont pas supprimés avant son raccordement. Les options
en fin de cette inspection documentent la discussion antérieure, désormais tranchée.

La pondération désigne un biais de fréquence entre cartes nécessitant une
présence physique (`DISTANCE_EXCLUE`) et cartes compatibles avec la distance.
Elle est distincte du filtrage d'éligibilité par mode et du piment.

## Deux implémentations distinctes

### Calcul de poids pur, sans appel de production trouvé

Fichier `lib/engines/draw/hybrid_draw_weighting.dart`, méthode
`HybridDrawWeighting.weights` (helpers `_group`, `_uniform`).

Elle reçoit un ensemble déjà éligible, le sépare en deux groupes selon
`distanceExcluded`, puis attribue :

| Orientation | Compatible distance | Distance exclue |
| --- | --- | --- |
| Distance | 70 % | 30 % |
| Face à face | 30 % | 70 % |

Dans chaque groupe, chaque candidate reçoit `part du groupe / effectif du groupe`.
Si un groupe est vide, l'autre reçoit une distribution uniforme de poids total 1.
Si les deux sont vides, le résultat est vide. Une carte `DISTANCE_EXCLUE` n'est
donc pas exclue par une orientation « distance » dans une session hybride.

Exemple : trois cartes compatibles distance et une carte physique, orientation
distance : chacune des trois reçoit environ 23,3 %, la physique reçoit 30 %.
Ce biais compense les tailles des groupes ; il ne rend pas tous les concepts
équiprobables.

`test/engines/hybrid_draw_weighting_test.dart` teste cette classe. Elle est exportée
par les moteurs ; la recherche dans `lib/` ne trouve aucun appel à cette classe.
Elle ne doit pas être confondue avec le mécanisme effectivement branché au réseau.

### Construction de deux paquets dans le runtime réseau

Fichier `lib/engines/deck/session_deck_builder.dart` :

- `HybridSessionDecks` appelle `_compose` deux fois avec 70 % puis 30 % de cartes
  physiques (`distanceExcluded == true`).
- Chaque paquet a la taille de la source. Le nombre de cartes physiques vaut
  `round(taille × part physique)` ; le reste provient du groupe compatible distance.
- `_repeatTo` parcourt chaque groupe dans son ordre courant, en boucle si besoin.
  Cela peut répéter des entrées et omettre une partie d'un groupe. Ce n'est pas un
  tirage uniforme de concepts distincts.
- Si un groupe est vide, chaque paquet reprend la source entière.
- `_compose` réattribue des IDs `cardId::variantId::ordinal`.
- `SessionDeckRuntime.draw` choisit un index aléatoire dans le paquet actif,
  privilégie les cartes hors de `avoidCardIds` si possible, puis enlève au plus
  une entrée de même identité dans l'autre paquet. Si le paquet actif est vide,
  il utilise l'autre paquet.

Dans `lib/features/game/network_game_controller.dart`, `_buildDeckCycle` construit
la source et les deux paquets ; `_refill` appelle `SessionDeckRuntime.draw` selon
`orientation`. Le changement passe par `switchOrientation`, puis
`SupabaseNetworkGameRepository.setHybridOrientation` et la RPC existante
`set_network_hybrid_orientation`. Les paquets privés sont persistés dans
`network_duel_secret_store.dart`.

Il s'agit de proportions initiales de paquets, pas d'une garantie 70/30 sur
chaque série de pioches : épuisement, suppression dans le miroir et évitement des
cartes récentes peuvent changer la distribution réelle.

## Règle de gameplay représentée

`docs/deck_builder_v3.md` décrit l'intention : dans une session hybride, changer
l'orientation favorise les propositions adaptées à la situation sans changer
la session, les PA ou les cartes déjà en main. Le libellé d'aide dans
`lib/features/game/ui/game_settings_panel.dart` dit que l'orientation adapte le
tirage aux conditions de la session.

« Compatible distance » ne signifie pas « exclusivement distance ». Ces cartes
peuvent aussi être proposées en présentiel si leurs autres contraintes passent.

| Mode | Filtrage de compatibilité | Rôle prévu de l'orientation |
| --- | --- | --- |
| DISTANCE | Les actions `DISTANCE_EXCLUE` doivent être filtrées | Aucun poids ne doit réautoriser une carte incompatible |
| PRESENTIEL | Cartes physiques et compatibles distance, sous leurs autres contraintes | Ce filtrage ne requiert pas à lui seul un biais 70/30 |
| HYBRID | `DISTANCE_EXCLUE` n'exclut pas le concept de toute la session | L'orientation était un biais de fréquence, pas un changement de mode ni une exclusion stricte |

Le filtrage est encodé par `CatalogEngineAdapter._v3Technical` :
`distanceExcluded` produit une règle `SESSION_MODE` autorisant `face_to_face` et
`hybrid`. `EligibilityEngine._technicalReason` la compare à `context.mode`.

Limite actuelle concrète : `NetworkGameController` initialise `_context` en
`SessionMode.face_to_face`, et `switchOrientation` ne change pas ce contexte.
Les deux paquets y sont construits sans condition sur un mode hybride.
La RPC vérifie l'orientation et l'appartenance à la session, sans imposer un mode
hybride. L'intention décrite ne prouve donc pas que la séparation des trois modes
soit correctement appliquée partout dans le runtime actuel. Aucune correction
de ce parcours n'est entreprise au Lot 1.

## Avec le futur tirage classe → concept uniforme

Cette pondération **n'est pas nécessaire au fonctionnement du nouveau modèle**.
Le filtrage de compatibilité reste nécessaire ; le biais 70/30 est une décision
de gameplay supplémentaire, indépendante des ratios de piment.

Sans biais, chaque concept candidat d'une classe a la même probabilité.
Avec un biais interne à la classe, deux concepts de la même classe peuvent avoir
des probabilités différentes selon leur groupe : cela modifierait l'uniformité
validée. Construire ou pondérer des groupes avant de choisir le piment peut, à
son tour, modifier les ratios de classes ou les classes disponibles.

Les options de décision sont donc :

1. supprimer le biais et conserver classe de piment → concept uniforme ;
2. conserver une préférence liée à l'orientation, en validant expressément son
   interaction avec les classes et la dérogation à l'uniformité éventuelle ;
3. choisir une autre règle d'orientation, qui serait une décision de gameplay
   distincte et ne doit pas être déduite automatiquement.

Même si l'intention de favoriser une orientation est conservée, la duplication
d'occurrences dans deux paquets ne doit pas être reconduite : elle contredit le
stock conceptuel unique et les quotas. Aucune de ces options n'est implémentée
en attendant la décision de l'utilisateur.
