# Lot 1 — contrat éditorial des concepts

Référence : [spécification consolidée fournie par l'utilisateur](../specs/consolidated_concepts.fr.txt).
Elle remplace les décisions contradictoires du dépôt. Le contrat ne contient
ni moteur de pioche, ni quota calculé, ni identité d'usage ou migration réseau.

## Sources et état du raccordement

- `assets/catalog/concepts/active.fr.json` : les **56 concepts actifs** et les zones.
- `docs/catalog/reserved_concepts.fr.json` : trois concepts réservés, sans actions
  jouables ; hors du catalogue actif et hors des assets de l'application.
- `lib/domain/catalog/concept_catalog.dart` : lecteur pur, immuable et strict du
  contrat actif. Il n'importe ni Flutter, ni Drift, ni les moteurs existants.

Les numéros éditoriaux `001` à `065`, avec leurs trous conservés, identifient les
concepts dans ce contrat. Les identités des définitions d'action sont locales au
concept (`003.stage.1`, `002.zone.neck_nape`, etc.). Ce ne sont pas des identités
d'usage : leur correspondance avec les anciens IDs persistés relève du lot 3.

Le catalogue ancien `assets/catalog/source/cards.v2.fr.json` et son lecteur
restent utilisés par le runtime existant. Le contrat nouveau n'est pas encore
branché à l'application ni déclaré dans `pubspec.yaml`. Le remplacer en production
ici obligerait à entreprendre les lots deck, réseau et UI interdits dans ce lot.
Il ne s'agit pas d'une deuxième implémentation de moteur. Les consommateurs
anciens et leur catalogue devront disparaître au fil de leur remplacement.

Le seed `cards.v1.fr.json`, sans lecteur de production ou test, est réellement
supprimé dans ce lot. Les anciens audits qui vérifient encore `cards.v2.fr.json`
restent avec leurs consommateurs jusqu'au remplacement de ceux-ci. Leur
conservation temporaire n'est pas une exigence de compatibilité historique.

## Statuts éditoriaux

| Numéro | Concept | Statut et raison |
| --- | --- | --- |
| 011 | Strip-tease complet | Supprimé : redondant avec 010 |
| 014 | Corps contre corps | Supprimé : trop proche de Câlin |
| 015 | Frottements habillés | Supprimé |
| 017 | Reproduire une posture | Supprimé : trop proche de 016 |
| 040 | Douche à deux | Supprimé |
| 041 | Bain à deux | Supprimé |
| 036 | Température | Réservé |
| 059 | Texture | Réservé |
| 064 | Dégustation sensuelle | Réservé |

Les trois réserves appartiennent au futur système commun Température / Texture /
Dégustation. Aucune des neuf sorties n'est cachée dans le catalogue actif derrière
un flag. Les six suppressions sont tracées dans ce tableau, sans définition jouable.

## Taxonomie

| `kind` | Définition | Conséquence éditoriale |
| --- | --- | --- |
| `action` | Une action, une variante | Aucun stade d'évolution |
| `evolution` | Deux ou trois `stages`, chacun avec son piment | Pas de copie de ces stades dans `variants` |
| `zones` | Concepts 002, 004, 005 ; base 1, variantes de zone et un choix libre | Le nombre de zones ne définit pas des évolutions |
| `accessory` | Concepts 049 à 052 ; variantes d'usage externe/phallus ou insertion | Aucune évolution ; axes zone/accessoire sans inventaire de matériel inventé |

Les variantes de sextoy représentent uniquement les catégories validées, pas la
liste finale des accessoires compatibles. Externe et phallus sont au piment 3,
insertions vaginale et anale au piment 4. Aucun modificateur générique n'est ajouté.

Pour les zones génériques : `min(4, piment intrinsèque + modificateur de zone)`.
Les 13 identifiants de zones transcrivent les groupes validés, en séparant pénis
et vulve pour permettre leurs choix distincts. Les vêtements ne sont pas une zone.
Le contrôle du plafond global et le calcul de classe de pioche sont au lot 2.

Les concepts 006 et 007 restent deux actions simples distinctes. Leur champ
`capacity_rule` référence la capacité vestimentaire spéciale ; aucune copie de
concept ni aucun calcul de capacité n'est ajouté au Lot 1.

Les champs `persistent_effect` et la contrainte `session_modes` de 058 transcrivent
les précisions explicites de la spécification. Ils ne remplacent pas le système
d'effets ni toutes les contraintes d'éligibilité existantes. Une absence de mode
dans ce contrat signifie « non précisé ici », pas « autorisé dans tous les modes ».

Les textes explicitent les distinctions demandées : Embrasser/S'embrasser,
bouche/main, tenue choisie par soi ou par l'autre, posture/pose, sexting/message
ponctuel, position à réaliser, strip-tease possible après rhabillage, exposition
subjective et gestes contrôlés. Les stades sans détail fourni restent nommés
« Stade 1/2/3 ». Aucune technique supplémentaire n'est inventée ; Supplier conserve
les trois formulations expressément fournies.

## Vérification

Les mêmes contrôles purs sont disponibles dans :

- `test/catalog/concept_catalog_contract_test.dart` pour le runner habituel ;
- `tool/check_concept_catalog.dart` pour un audit Dart sans dépendance externe.

Commande depuis la racine : `dart tool/check_concept_catalog.dart`.

Ils couvrent notamment les 56 identités, réserves/suppressions, toutes les suites
de piments, toutes les zones, la séparation variantes/évolutions, les capacités
006/007, les distinctions textuelles, l'immuabilité et le rejet de données mal
formées ou d'anciens flags. Résultat : **23/23 contrôles réussis**.
Répartition par premier piment : **26 / 11 / 17 / 2** ; cumul : **26 / 37 / 54 / 56**.

L'analyse ciblée du lecteur, des contrôles partagés et de l'outil d'audit ne
signale aucun problème. Le lancement de la même suite via `package:test` a été
tenté : échec au chargement par refus d'accès lors de la copie du noyau compilé
dans le répertoire temporaire du sandbox. Les 23 contrôles ont bien été exécutés
par l'audit direct, mais le runner habituel n'est pas déclaré fonctionnel.

Cet audit utilise le SDK Dart déjà présent. Aucun changement d'architecture ou
de dépendances pour contourner les problèmes locaux de tests n'a été effectué.
Les limitations antérieures de Flutter/shared_preferences/Drift restent consignées
dans `docs/concept_transition_baseline.json` et ne sont pas déclarées résolues.

## Préparation du lot 2

Décision supplémentaire validée : normaliser les poids sur les seules classes
autorisées **et possédant au moins un candidat**. Une classe vide perd son poids,
redistribué proportionnellement aux classes restantes. Sans aucun candidat,
passer à la logique de cycle/épuisement, sans repêcher de concept épuisé.

La pondération hybride est suspendue à une décision de l'utilisateur. Voir
[l'inspection détaillée](../hybrid_weighting_review.md). Aucun code de pioche,
quota runtime, RPC, stockage de session, écran ou pondération hybride n'a changé.
