# Reprise du modèle de cartes conceptuelles — 15 octobre 2026

Mise à jour après réception de la spécification consolidée : les paragraphes
ci-dessous conservent l'audit initial du Lot 0. Les décisions manquantes ont été
fournies et le Lot 1 est décrit dans le [contrat catalogue](catalog/concept_contract.md).
La [spécification consolidée](specs/consolidated_concepts.fr.txt) fait autorité.

Le découpage courant remplace le regroupement initial ci-dessous :

1. Contrat catalogue — 56 actifs, 3 réservés, 6 supprimés, taxonomie et tests purs.
2. Deck pur — concepts, classes, ratios, quotas et cas 006/007.
3. Identité d'usage et snapshot — persistance, reprise, historique.
4. Serveur — adaptation par nouvelles migrations uniquement.
5. Runtime/UI — choix dynamiques des stades et variantes.
6. Parcours secondaires — enchères, compromis, corruption, Recovery et apprentissage.
7. Nettoyage final — références mortes, analyse et vérifications d'ensemble.

Décision validée pour le Lot 2 : les classes autorisées mais vides perdent leur
poids, redistribué proportionnellement aux classes autorisées non vides.
Sans candidat, appliquer la logique de cycle/épuisement, sans fallback vers
une carte épuisée. La décision HYBRID est désormais validée : supprimer le
biais 70/30 et les deux paquets dans le moteur neuf ; l'orientation sert
uniquement à l'admissibilité. Voir [l'inspection historique](hybrid_weighting_review.md).

Le [Lot 2 — moteur pur](concept_deck_engine.md) est livré sans raccordement au
runtime, à l'UI ou au réseau. Les structures anciennes encore consommées sont
conservées jusqu'au raccordement ; leur liste et leurs dépendances sont tracées.

Le [Lot 3 — usages et checkpoint](concept_usage_persistence.md) introduit le
snapshot immuable, le retry par intention et la sérialisation locale du stock
avec ses usages. Aucun SQL ni contrat réseau n'est modifié. Le choix du stockage
canonique du runtime et du futur contrat réseau reste à valider avant raccordement.

Le besoin de convertir d'anciennes sessions ne justifie pas de conserver deux
moteurs pour des sessions de développement sans valeur. Les limitations locales
des tests ne doivent provoquer aucun changement d'architecture ou de dépendances
sans validation préalable.

## État de ce lot

Lot 0 : inspection et préparation uniquement. Aucun comportement du jeu,
catalogue chargé ou format de session n'a été modifié. Point de départ Git :
`0aba154` (`content: finalize first ENCHAIRE card set`). Arbre propre à la reprise.

Référence éditoriale : conversation « Conception dapp adulte suite »,
`6ac5ea4a-d394-83ed-a82d-485eb61fe04d`, et demande de reprise du 15 octobre.
La lecture de cette conversation ne restitue que ses cinq derniers échanges,
sans curseur vers les échanges antérieurs. Ne pas reconstituer les validations
manquantes à partir des suggestions de l'assistant ou du catalogue antérieur.

## Décisions récupérées

- Cible : **56 concepts actifs**. Les suppressions, réserves et évolutions
  validées doivent être transcrites depuis leur source complète.
- Remplacer le modèle courant par **concept + quota + usage snapshot**.
  Les détails de quota et de snapshot ne figurent pas dans les échanges récupérés.
- Un concept ne compte qu'une fois dans la pioche, quel que soit son nombre
  de stades. Le stade se choisit après la pioche parmi ceux accessibles.
- Le piment global fixe un plafond impératif d'action. Le style règle la
  fréquence des classes de pioche, sans imposer le stade effectivement joué.
- Classe d'une action simple : son piment. Classe d'une évolution : maximum
  des piments de ses stades actuellement accessibles.
- Pour une zone libre : `max(1, piment maximal actuellement accessible - 1)`.
  Cette réduction concerne seulement la classe de pioche, jamais le piment
  réel de l'action choisie ni son admissibilité sous le plafond global.
- Pas de champ éditorial subjectif `drawSpice`.
- Ratios conservés sur les classes 1/2/3/4 : Soft `45/40/13/2`,
  Épicé `20/40/30/10`, Intenable `10/25/40/25`.
- Tirer d'abord la classe, puis uniformément le concept de cette classe.
  Redistribuer proportionnellement les poids des niveaux verrouillés.
- Exemple récupéré : Photo mutuelle `1/2/4` appartient à la classe 2 au
  global 3, puis à la classe 4 au global 4 ; elle reste un seul concept.
- Exemple récupéré : zone libre de base 1 avec zones +0/+1/+2 : classes
  de pioche `1/1/2/2` aux plafonds globaux `1/2/3/4`.

Ne pas ajouter d'anti-triche, de mécanique ou d'équilibrage non validés.
Les migrations Supabase existantes sont immuables ; tout changement requis
passera par une nouvelle migration. Aucun déploiement dans ce lot.

## Mini-planning et critères de sortie

| Lot | Travail | Vérification avant checkpoint Git |
| --- | --- | --- |
| 0 — cadrage | Inspecter le dépôt, tracer les écarts, préparer la suppression et identifier les validations absentes | Référence de tests existants et diff limité à la préparation |
| 1 — catalogue | Transcrire les 56 concepts, leurs stades, zones et statuts ; remplacer le contenu antérieur et les audits devenus faux | 56 identités uniques, références valides, exclusions et piments conformes à la source validée |
| 2 — domaine et pioche | Introduire concept/quota/usage selon le contrat récupéré ; remplacer les chemins de pioche concernés | Une entrée par concept, plafond global, classes dynamiques, ratios par classe indépendants du nombre de concepts et de stades, épuisement selon quotas validés |
| 3 — parcours et reprise | Adapter sélection, main, duel, enchères, corruption, Recovery, défausse et sauvegardes | Scénarios locaux ciblés ; usage engagé stable ; aucune consommation ou sélection modifiée à la reprise |
| 4 — réseau et nettoyage final | Adapter les échanges, ajouter les migrations requises, retirer les anciens modèles et outils restants | Tests de reconnexion et parcours réseau, migrations historiques identiques, absence de chemins de production obsolètes |

Ces lots sont des unités de revue ; scinder un lot si son diff ne reste pas
contrôlable. Faire les changements liés et leurs suppressions dans le même lot
compilable, puis tests ciblés et commit. Ne pas laisser deux modèles de
production en parallèle à la fin de la transition.

L'ordre exact entre catalogue et modèle dépend de la forme validée du nouveau
catalogue : ne pas forcer les 56 concepts dans le schéma ancien pour obtenir
artificiellement un premier lot indépendant.

## Inspection du dépôt

| Zone | État observé | Travail à préparer |
| --- | --- | --- |
| Catalogue chargé | `CatalogLoader.load` et `pubspec.yaml` chargent `cards.v2.fr.json` | Remplacer la source réellement chargée, pas uniquement une documentation |
| Volume | 120 définitions, 237 variantes brutes ; adaptateur V3 : 96 cartes et 141 variantes activées via les flags V3 | Le catalogue actuel n'est pas celui des 56 concepts ; ne pas confondre les flags historiques `enabled` avec `v3_deck_enabled` |
| Référence locale V4 | `../ENCHAIRE_catalogue_cartes_reconstruit_v4.txt` annonce 65 cartes | Référence antérieure, insuffisante pour décider quelles neuf cartes retirer |
| Modèles éditoriaux | `lib/domain/catalog/definitions.dart` conserve variantes, flags et liens `v3Replacement*` | Remplacer les couches superposées après analyse des lecteurs |
| Adaptateur | `CatalogEngineAdapter` expose deux chemins via `useV3` | Identifier les consommateurs à migrer avant suppression du chemin historique |
| Pioche locale | `lib/engines/draw/draw_engine.dart` additionne histoire, style, piment, diversité et fréquence | Cette formule ne garantit pas les ratios de classes validés ; la remplacer sur les parcours concernés |
| Paquet réseau | `_buildDeckCycle` dans `network_game_controller.dart` examine le contexte au piment 5 ; `_networkCard` prend la première variante éligible | Reporter la résolution des choix au bon moment ; calculer l'accessibilité et la classe avec le plafond réel |
| Construction du paquet | `session_deck_builder.dart` matérialise des copies `cardId::variantId::ordinal`, applique pénuries/substitutions et limite de copies | Retirer ce mécanisme là où le quota conceptuel le remplace ; vérifier séparément les règles de cycle/hybride validées |
| Styles | `BalanceConfig.styleDistributions` et `_targetBySpice` utilisent encore cinq niveaux | Remplacer l'application des poids, pas simplement leurs constantes |
| Engagement | `CombatValueSnapshot` fige valeur, rôle et variante ; les DTO réseau transportent aussi occurrence et direction | Ce snapshot existant n'est pas à lui seul le nouveau snapshot d'usage |
| Reprise réseau privée | `NetworkPrivateGameState` dans `network_duel_secret_store.dart` sauvegarde cartes, deux paquets, engagement actif, cycle, historique et directions | Tester la reprise avant toute suppression de format ou reconstruction du paquet |
| Reprise locale | `SessionRepository` et schéma Drift version 3 persistent cartes/variantes, rounds et snapshots | Examiner les deux stockages : le réseau privé utilise aussi SharedPreferences |
| Supabase | 11 migrations, de `202609290001_two_phone_lobby.sql` à `202610030001_directional_occurrence_pa.sql` | Les conserver octet pour octet ; ne pas déduire leur état de déploiement de leur seule présence |
| Tests existants | Certains figent 96 cartes/141 variantes et les anciens rapports éditoriaux | Remplacer les assertions et fixtures devenues fausses avec le code correspondant |

## Suppression réelle : périmètres à examiner

1. Remplacer le catalogue actif, puis retirer les entrées supprimées de cette
   source. Ne pas simplement les masquer derrière de nouveaux flags.
2. Examiner `cards.v1.fr.json`, les anciens rapports `docs/catalog_v3_*`, les
   scripts `tool/audit_catalog_v3*` et leurs tests : certains restent réellement
   consommés. Remplacer ou retirer ensemble les fichiers et leurs lecteurs.
3. Examiner les liens de remplacement dans `roleplay_scenarios.dart` et
   `v3_coverage.dart`. Leur présence ne prouve pas un besoin de reprise de
   sessions ; ne pas conserver tout l'ancien catalogue pour ces seuls audits.
4. Retirer les chemins de variantes préchoisies et les formules de pioche
   remplacées, avec leurs exports, appels, fixtures et documentation périmée.
5. Préserver les données historiques nécessaires à un engagement existant sans
   en faire des candidats des nouvelles parties. La forme technique de cette
   préservation reste à choisir après examen de la reprise.

L'historique Git conserve les versions retirées. Ne rien modifier sous le
répertoire synchronisé `../sources/`.

## Choix à signaler avant modification architecturale

- Contrat exact du quota : portée, consommation, remise à disposition et lien
  au cycle. Récupérer la décision antérieure avant de choisir une représentation.
- Contenu et instant de gel d'un usage snapshot : stade, zone, direction,
  valeur, texte/version, paramètres ; retrouver la liste validée, puis signaler
  les choix de stockage qui restent ouverts.
- Reprise des anciennes sessions : conversion ponctuelle, contenu historique
  localisé ou autre solution minimale, à déterminer avec une fixture réelle.
  Ne pas annoncer de suppression de compatibilité avant d'avoir testé la reprise.
- Classes sans candidat après consentements, matériel ou quotas : le cas des
  niveaux verrouillés est défini ; le traitement d'une classe autorisée mais
  vide n'est pas explicité dans les échanges accessibles.
- Interaction des nouveaux ratios avec l'orientation hybride et les règles de
  cycle existantes : retrouver les décisions précédentes avant de les modifier.

## Informations nécessaires pour ouvrir le lot de remplacement

Obtenir le récapitulatif validé ou l'export complet donnant les 56 concepts,
les suppressions/réserves, les évolutions/piments/zones et le détail du modèle
concept/quota/usage snapshot. Une demande a été adressée à l'utilisateur.
En attendant, aucun identifiant final, quota ni décision éditoriale n'est inventé.

Le résultat des vérifications du lot 0 est enregistré dans
`docs/concept_transition_baseline.json`, avec les empreintes des migrations
historiques. Ces empreintes sont un constat de fichiers locaux, pas une preuve
de déploiement Supabase.

Les quatre suites ciblées (règles V3, cycle réseau, repository de session et
migration locale) ont échoué au chargement : aucun test exécuté. Le lancement
Flutter rencontre une erreur de connexion locale `127.0.0.1` et la résolution
des dépendances échoue notamment pour `shared_preferences` et `drift`.
Rétablir les dépendances et l'exécution locale puis relancer cette référence
avant le premier changement fonctionnel. Ne pas qualifier ce checkpoint de
référence fonctionnelle verte. Le contrôle du diff et la vérification des onze
empreintes de migrations ont réussi.
