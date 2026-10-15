# Lot 2 — moteur de deck conceptuel pur

Références : [spécification consolidée](specs/consolidated_concepts.fr.txt),
[contrat catalogue](catalog/concept_contract.md), puis décisions utilisateur sur
les classes vides et la suppression du biais HYBRID.

## Périmètre livré

`lib/engines/deck/concept_deck_engine.dart` est exporté par les moteurs mais
n'est appelé par aucun runtime de jeu. Le catalogue, le réseau, l'UI, les RPC,
les dépendances et les parcours secondaires n'ont pas été raccordés ou modifiés.
Les anciennes structures encore utilisées restent intactes.

L'ordre de préparation est :

1. concepts avec quota restant et non signalés comme indisponibles ;
2. actions/zones explicitement admissibles dans le contexte courant ;
3. actions sous le plafond global et classe dynamique de chaque concept ;
4. retrait des classes vides et normalisation sur les seules classes présentes ;
5. tirage d'une classe selon le style ;
6. tirage uniforme d'un concept de cette classe.

Un concept a une seule entrée dans le stock et au plus une candidate. Le nombre
de variantes, de zones ou de stades n'est jamais utilisé comme multiplicité ni
comme poids. Les définitions accessibles accompagnent la candidate sans qu'une
variante, un stade, une zone ou une direction soit choisi par le tirage.

## API et responsabilités

- `ConceptDeckStock.startCycle(catalog, initialClothing)` initialise un stock
  immuable pour un joueur et un cycle. Le nouveau moteur n'invente pas la règle
  de passage au cycle suivant et ne réinitialise jamais le stock automatiquement.
- `ConceptDeckEligibility` fournit les IDs des actions et zones admissibles,
  indexés par concept. C'est une entrée explicite issue de l'éligibilité du
  contexte/orientation, des préférences et du matériel ; une entrée absente est
  interdite. Le Lot 1 ne contient pas encore toutes les contraintes de ces
  systèmes, et le Lot 2 ne réécrit pas leur moteur ni leur raccordement.
- `ConceptDeckEngine.prepare` prend ce stock, cette admissibilité, le plafond
  global, le style et les éventuels concepts indisponibles (déjà en main ou
  réservés par le futur orchestrateur). Il produit un pool immuable.
- `ConceptDeckPool.draw(Random)` tire une candidate ou retourne `null` si le
  pool est vide. Il ne consomme pas le quota et ne réserve pas le concept.
- `ConceptDeckStock.consume(conceptId)` retourne le stock après une utilisation
  réellement engagée. Il ne consomme aucun stade et interdit de passer sous zéro.
  L'identité d'usage et la déduplication des retries restent au Lot 3 : ce compteur
  n'est pas, à lui seul, un protocole d'engagement idempotent.

Le pool est un calcul à un instant donné. Après modification du stock, du
plafond, des concepts détenus ou de l'admissibilité, l'appelant doit refaire
`prepare` avant le prochain tirage. Le changement de plafond expose alors les
nouveaux choix sans changer le concept ni son quota. Aucune persistance ou
logique d'écran n'est introduite pour cela dans ce lot.

## Quotas et vêtements

Un concept à N stades d'évolution a N utilisations par cycle, même si tous ses
stades ne sont pas encore accessibles. Un concept sans évolution a normalement
une utilisation ; les variantes de zones et de sextoy ne sont pas des stades.
On peut choisir plusieurs fois le même stade tant que le quota reste positif.

006 et 007 sont deux entrées distinctes de capacité :

- `cap006 = min(2, T)` ;
- `cap007 = ceil((T - cap006) / 2)` ;

où T est le nombre initial de vêtements de ce joueur. Les tests couvrent T de
0 à 8, notamment les capacités nulles et les valeurs impaires. Ces capacités
ne créent aucune copie dans le stock. La disponibilité vestimentaire courante
reste une contrainte d'éligibilité à fournir par le système existant.

## Piment et probabilités

Chaque choix accessible doit respecter le plafond global 1 à 4. La classe
d'une candidate est le piment maximal des choix actuellement accessibles.
Pour les concepts génériques de type `zones` (002, 004, 005, avec choix libre),
elle devient `max(1, maximum accessible - 1)`. Le piment des actions ne change
pas : bras = 1, cuisses = 2, pénis/vulve = 3 pour une base 1.

Les pratiques intrinsèques et les variantes sextoy n'utilisent pas ce rabais
ni un supplément de zone. Exclusions d'un stade, d'un accessoire ou d'une zone
peuvent diminuer le maximum accessible, donc la classe.

| Style | Classe 1 | Classe 2 | Classe 3 | Classe 4 |
| --- | ---: | ---: | ---: | ---: |
| Soft | 45 | 40 | 13 | 2 |
| Épicé | 20 | 40 | 30 | 10 |
| Intenable | 10 | 25 | 40 | 25 |

Pour chaque classe présente, probabilité = son poids / somme des poids présents.
Cela traite de la même façon les classes verrouillées, exclues ou vidées par
les quotas. Aucun candidat signifie pool vide : le moteur retourne le contrôle
à l'orchestrateur de cycle, sans substitution de piment, reprise d'un concept
épuisé ou pondération secondaire.

La décision HYBRID est appliquée : pas de poids 70/30, pas de paire de paquets,
pas de répétition pour compenser un groupe. L'orientation ne peut changer les
probabilités qu'en changeant les concepts/actions/zones admissibles à l'entrée.

## Vérifications du lot

`test/engines/concept_deck_engine_test.dart` enregistre les mêmes contrôles purs
que `tool/check_concept_deck.dart`. Résultat de l'audit direct : **31/31**.
Régression catalogue : **23/23**. Analyse ciblée : aucun problème.

Les contrôles incluent les formules 006/007, trois répétitions du même stade,
la non-consommation à la pioche, les classes Photo mutuelle `1/2/2/4`, Entrave
`1/2/3/3`, zones `1/1/2/2`, les plafonds réels, toutes les pondérations et leur
normalisation, les exclusions, l'épuisement et l'immuabilité. Un test utilise
10 000 points aléatoires stratifiés avec indices contrôlés pour vérifier les
pourcentages et l'égalité de sélection des concepts, sans test statistique fluctuant.

Les limites locales du runner habituel et des dépendances restent documentées
dans les checkpoints des Lots 0 et 1. Elles ne sont pas déclarées résolues ;
aucun nouveau contournement de dépendances ni modification d'environnement
Flutter n'est réalisé dans ce lot.

## Structures techniquement remplaçables, suppressions différées

Recherche effectuée dans `lib/`, `test/` et `tool/` avant de décider des retraits.
La nouvelle logique peut remplacer les responsabilités suivantes, mais son
raccordement effectif reste à faire :

| Ancien élément | Remplacement | Consommateurs qui empêchent sa suppression immédiate |
| --- | --- | --- |
| `DeckCandidateV3`, copies `contentKey::ordinal` et `SessionDeckBuilderV3.build` | Stock par concept, quotas, `prepare` | Contrôleur réseau et codecs des paquets privés, tests de cycle et de reprise |
| `HybridSessionDecks._compose` / `_repeatTo` | Un seul ensemble logique de candidats | `_buildDeckCycle` dans le contrôleur réseau |
| `SessionDeckRuntime.draw`, deux listes et suppression dans le miroir | `ConceptDeckPool.draw` sur un pool actualisé | `_refill` et état privé réseau |
| `_targetBySpice` et application des poids à cinq niveaux | Classes dynamiques et normalisation à quatre niveaux | Contrôleur réseau et ancien `BalanceConfig` |
| `DrawEngine._weight`, `DrawWeights` et pondération par histoire/diversité/fréquence | Classe puis concept uniforme | Jeu local, contrôleur de duel réseau initial et simulation ; retirer leurs usages lors du raccordement |
| `HybridDrawWeighting.weights` | Aucune pondération hybride dans le moteur neuf | Aucun appel de production trouvé ; export et tests dédiés subsistent. À retirer avec le nettoyage de cette famille lors du raccordement |
| `DeckSubstitution`, pénuries et compléments par classes voisines | Classes vides retirées, poids renormalisés | `DeckShortage` encore stocké, exposé et consommé par le réseau et l'UI |

Ne pas supprimer tout `session_deck_builder.dart` en bloc : ce fichier contient
aussi `HybridDeckOrientation`, `DeckExhaustionChoice` et `DeckCycleState`, encore
utilisés par les DTO, RPC, écrans et règles de continuation. La suppression de
70/30 n'implique pas celle de l'orientation ou des choix de fin de cycle.

La règle de seconde utilisation via DISCARD/EXHAUSTED est remplacée par le quota
dans le moteur nouveau, mais ses fonctions du lifecycle ne sont pas retirées ici :
elles servent encore les parcours de corruption/Recovery et requièrent le Lot 6.
L'éligibilité, les directions, les snapshots, PA et effets existants ne sont pas
techniquement remplacés par ce seul moteur de deck.

## Point à traiter au raccordement réseau

`NetworkGameController` initialise encore `_context` en `SessionMode.face_to_face`.
`switchOrientation` met à jour l'orientation sans modifier ce contexte. Il faudra
faire produire l'admissibilité à partir du contexte/orientation réel avant
d'appeler le moteur nouveau. Ce problème est consigné et n'est pas corrigé au Lot 2.
