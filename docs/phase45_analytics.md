# Phase 4.5 — événements locaux et statistiques descriptives

Cette phase complète la Phase 4 (`27f5acb94532408631e2bb2c64ff2232a3a32514`).
Elle ne fournit ni profils humoristiques, ni diagnostic, ni UI Phase 5. Les
moteurs de règles et `BalanceConfig` restent inchangés : 100 PA initiaux et main
cible de quatre cartes. Aucun réseau, média ou asset illustré n'est ajouté.

## Contrat et intégration

`GameEvent.record` produit une enveloppe `event_version: 2`, avec `type`,
`visibility`, `owner_player_id` éventuel, `facts` et `private_analytics`.
Les faits et listes internes sont copiés et gelés. Le constructeur historique
reste disponible (version 1, visibilité interne, aucune observation déduite).

`SessionTelemetry` reçoit un identifiant de session, une horloge et un sink
local de `StoredEvent`. Il génère des identifiants et séquences ordonnés sans
aléatoire. À la reprise, fournir `lastSequence` depuis le journal persistant.
Une erreur du sink n'avance pas la séquence. Pour une écriture asynchrone,
collecter les événements d'une commande puis utiliser `appendAll` dans la
transaction de persistance appropriée ; ce collecteur synchrone n'est pas une
file durable et ne garantit pas à lui seul l'atomicité état/journal.

Le simulateur utilise ce même contrat via le callback facultatif `onEvent`.
Les événements historiques alimentent toujours les métriques Phase 4 ; la
télémétrie enrichie est collectée séparément et ne consomme aucun nombre
aléatoire. Les futurs contrôleurs de partie devront appeler le collecteur à
leurs frontières de commandes validées. Les moteurs purs Phase 3 ne sont pas
transformés en services de stockage ni remplacés.

Une `DecisionOpportunity` représente une décision effectivement disponible,
établie par les filtres métier existants, avec un identifiant de corrélation.
Elle ne donne aucune autorisation supplémentaire. Le même identifiant relie
`OPPORTUNITY`, `ATTEMPT`, `ACCEPTED`, `COMPLETED` ou `EXCLUDED`. Le contexte privé
conserve propriétaire, axe, motif neutre éventuel, snapshot engagé, montant et
PA disponibles, choix éligibles, tags éligibles et choix effectués.

## Faits disponibles

| Famille | Événements et contenu |
|---|---|
| Opportunités | `DECISION_OPPORTUNITY`, `DECISION_PASSED` : joueur, type de décision, round et corrélation ; choix disponibles dans le contexte privé |
| Style | `PLAYER_STYLE_CHANGED` : joueur, styles précédent et suivant, sans raison |
| Intensité | `CHILI_INCREASE_PROPOSED/ACCEPTED/DECLINED`, équivalents `DECREASE`, puis `CHILI_LEVEL_CHANGED` ; niveaux, destinataire et décision `INTENSITY_ONLY` |
| Enchères | `AUCTION_COMMITTED/RESOLVED` : joueur, montant, `COUNTER` ou `FINAL_DEFENSE`, `OWN_CARD` ou `INVERT_WINNER_CARD`, gagnant et succès ; opportunités inutilisées conservées |
| Inversion | `INVERSION_ATTEMPTED/RETAINED` : variante, rôles avant/après ; aucune modification du snapshot de puissance |
| Corruption | `CORRUPTION_PROPOSED/RESOLVED` : proposant, destinataire, objectif, éléments de l'offre, source DISCARD, ordres et identifiants d'action, répétitions, taille de combinaison, visibilité VISIBLE/MYSTERY, acceptation/refus |
| Exécution | `ACTION_EXECUTION_RECORDED` : identifiant d'action, carte/variante, volontaire initial, rôles prévus/effectifs, statut et motif ; sources `NORMAL_DUEL`, `AUCTION_RESULT`, `CORRUPTION`, `RECOVERY`, `RECOVERY_CONDITION` |
| Recovery | `RECOVERY_PROPOSED/RESOLVED` : opportunité, réponse, carte/variante et condition, source CATALOG/HAND/DISCARD, exception chili, PA avant/gain/après, statut |
| PA | `PA_SPENT` : source de dépense et soldes ; `MUTUAL_PA_EXTENSION` : joueurs, montant égal, soldes avant/après |
| Renoncement | `STRATEGIC_RENUNCIATION` : joueur, round et contexte des sélections avant engagement, séparé du STOP |
| Tirage/engagement | `CARD_DRAWN_PRIVATE` : carte, tags, précision, variantes accessibles/chili ; `CARD_LOCK_CHANGED_PRIVATE` : verrou ; `CARD_COMMITTED` : rôle volontaire et snapshot personnel figé |

Une offre composée utilise un identifiant distinct par occurrence, même si une
carte est répétée. L'exécution d'une promesse reprend cet identifiant. L'action
centrale obtenue après négociation peut aussi avoir la source CORRUPTION sans
être un élément promis : elle possède sa propre corrélation et aucune
observation PROMESSE. La politique Phase 4 ne simule que des offres simples ;
les tests du collecteur couvrent combinaison, répétition et mystery.

Les acceptations chili du simulateur correspondent aux transitions acceptées
par le moteur (notamment solvables). Le collecteur permet aussi de conserver
une réponse humaine sans changement effectif de niveau. La politique Phase 4
ne produit pas de refus de baisse ; ce cas est couvert directement par test.

## Confidentialité

Trois classes explicites : `PUBLIC`, `PLAYER_PRIVATE`,
`SESSION_PRIVATE_INTERNAL`. Une donnée interne n'est jamais une autorisation
d'affichage ou d'envoi. Les observations privées appartiennent à un joueur ;
un événement PLAYER_PRIVATE ne peut contenir les observations d'un autre.

`publicProjection()` refuse par défaut. Seuls les identifiants de round des
ouvertures/clôtures et les niveaux des changements chili explicitement PUBLIC
sont autorisés. Même une enveloppe PUBLIC ne transmet jamais son contexte
analytique ou ses autres champs. `PublicState` Phase 3 reste inchangé : aucune
main, note, préférence de style, base de consentement, raison/auteur d'exclusion
ou profil privé n'y est ajouté. Les résultats `PlayerBehaviorMetrics` restent
PLAYER_PRIVATE. Le journal complet ne doit jamais servir de DTO réseau.

Le stockage reste local dans la base existante, sans nouveau chiffrement ni
authentification. Le filtrage par propriétaire est une frontière de domaine,
pas une vérification d'identité. L'opt-in de partage des profils, la politique
de conservation et la protection du fichier local restent à définir avant une
fonction de partage. Les clés média et références photo/vidéo sont rejetées,
y compris imbriquées ; aucun média n'est produit ou enregistré par ce contrat.

## Calcul pur et sources des 19 axes

`AnalyticsEngine.compute(playerId, events)` renvoie `PlayerBehaviorMetrics` :
identifiant privé et map des 19 axes. Chaque `AxisMetrics` expose opportunities,
attempts, accepted, completed, excluded_neutral, sample_size, status, ratios
d'essai/acceptation/réalisation, montants et montant disponible, valeur moyenne
personnelle engagée, choix/tags distincts, couverture des choix éligibles,
répétitions volontaires et part du choix le plus fréquent.

| Axes | Observations descriptives |
|---|---|
| AUDACE, PRUDENCE | Valeur /20 et rôle du `CombatValueSnapshot` volontaire au commit ; jamais de renotation rétroactive |
| DEPENSE_PA, ECONOMIE_PA | Montants dépensés relativement aux PA disponibles lors des dépenses ; sources duel/enchère/chili |
| NEGOCIATION | Opportunités de contre-enchère/défense et utilisation/réussite |
| TENTATION | Opportunités de proposer une offre et propositions |
| PROMESSE | Occurrences promises, acceptées puis réalisées avec la même corrélation |
| REALISATION | Actions proposées/exécutées et statuts qualifiés |
| INVERSION | Possibilités, tentatives et inversions retenues |
| INITIATIVE, RECEPTIVITE | Rôles choisis puis effectivement exécutés pendant la session ; aucune préférence globale déduite |
| VARIETE, SPECIALISATION | Choix face à au moins deux cartes éligibles, diversité des cartes/tags, concentration et répétitions |
| ESCALADE, MODERATION | Opportunités et propositions de hausse/baisse chili, réponses et changement effectif |
| RECOVERY_RISK | Recovery légalement accessible, proposé, accepté et réalisé |
| PROLONGATION | Opportunités et extension mutuelle réalisée |
| RENONCEMENT_STRATEGIQUE | Renoncements avant engagement parmi les occasions de jouer |
| CHANGEMENT_STYLE | Décisions de style disponibles et changements réels |

Le ratio d'essai est `attempts/opportunities` : 3/3 vaut 1, 3/20 vaut 0,15.
Les stages sont dédupliqués par propriétaire/axe/opportunité, même au rejeu.
L'ordre de réception n'affecte pas le calcul. Des snapshots, montants ou choix
contradictoires pour la même décision déclenchent une erreur explicite.

Le seuil technique par défaut est **3 opportunités**, configurable et non
validé statistiquement. En dessous, le statut est `INSUFFICIENT_DATA` et les
ratios essai/acceptation/réalisation sont nuls. Les données brutes restent
inspectables ; ce seuil ne constitue ni un niveau de confiance statistique,
ni une calibration des profils. Les autres descripteurs ne sont pas des scores.
DEPENSE_PA/ECONOMIE_PA décrivent les décisions ayant une dépense ; leur ratio
d'essai n'est pas un score d'économie ni une proportion de tours dépensiers.

## STOP et neutralité

`CONSENT_STOP`, `PRACTICE_REFUSAL`, `CONSENT_WITHDRAWN`, `PROFILE_EXCLUSION`,
`TECHNICAL`, `CONTEXTUAL` et `UNKNOWN` excluent intégralement la décision du
numérateur ET du dénominateur. Un STOP force ce traitement. Un SKIP sans raison
connue est neutre par prudence ; un SKIP explicitement STRATEGIC peut rester
descriptif. Le motif demeure privé, jamais une explication publique d'exclusion.

Un refus Recovery ou d'une promesse de corruption ne crée pas un échec intime
noté. Le fait de proposer peut rester descriptif pour son auteur ; l'absence
de réalisation pour refus ne dégrade pas son ratio. Un petit pool sans choix
réel n'alimente ni variété ni spécialisation. Les choix de note /20 concernent
uniquement les pratiques déjà acceptées et ne mesurent jamais le consentement.

## EventLog et compatibilité

Aucune migration SQL : la base reste en version 2. Seule l'enveloppe JSON du
payload devient version 2. L'ordre, l'unicité, les transactions et le rejeu
idempotent de `EventLogRepository` sont conservés. `gameEventsForSession`
reconstruit les événements métier ; les payloads historiques sans enveloppe
restent lisibles et ne créent pas artificiellement d'observations analytiques.

Les versions futures/types métier inconnus sont rejetés explicitement par le
décodeur typé ; `forSession` reste une lecture brute pour inspection/récupération
des événements d'extension existants. Une nouvelle enveloppe invalide n'est pas
insérée. Aucun historique de développement n'est supprimé ou réécrit.

## Données pour le futur écran

`GameScreenProjection` fournit PA propres, temps écoulé et durée indicative,
chili actif, accès aux réglages, main cible de quatre, défausse propre et
actions révélées. Les cartes ont verrou, catégorie, clés titre/description,
chili des variantes, détails d'instructions, note personnelle et
`illustrationKey` facultatif. Les métadonnées absentes restent nulles ; aucune
illustration n'est inventée. Ces listes de niveaux sont des métadonnées du
catalogue, pas une nouvelle autorisation de jouer une variante.

Pendant une transition sur téléphone partagé, main, défausse, PA et notes sont
masqués. Une action centrale publique ne comporte aucune note personnelle.
Le timer et l'écran restent à implémenter en Phase 5 ; aucune navigation ou UI
Flutter significative n'est ajoutée ici.

## Régression et limites

Le rapport [phase45_regression.json](phase45_regression.json) compare 1 000
sessions, seeds **410000–410999**, au fichier conservé lors de la Phase 4.
L'égalité est exacte sur `metrics`, `byScenario`, `balance`, `scenarios`,
`limits`, `policy`, `profileSpecs`. La durée d'exécution n'est pas comparée.
Le rapport de couverture des tags de l'ancien benchmark avait une ancienne
erreur d'alias corrigée en Phase 4 ; il est exclu de la comparaison métier.

| Indicateur | Phase 4 = Phase 4.5 |
|---|---:|
| Duels | 46 304 |
| Passage 50 % PA A, duels | 9,438722966014419 |
| Passage 50 % PA B, duels | 10,13874614594039 |
| Contre-enchères | 31,10314443676572 % |
| Recovery/session | 23,516 |
| Mains de quatre | 95,88118561053876 % |

La collecte produit 1 318 722 événements et l'agrégation couvre 1 000 sessions.
La politique Phase 4 sélectionne ici des règles GENERAL : elle ne fournit
aucune observation INITIATIVE/RECEPTIVITE. Le moteur retourne donc des données
insuffisantes, sans inventer de rôles. Les tests directs couvrent les rôles
FAIRE/RECEVOIR et les cinq sources. Une étude de rôle plus représentative reste
un travail de simulation futur, sans altérer la baseline de cette mission.

Pour reproduire : `dart run tool/analytics_regression.dart <reference1000.json>`.
Le fichier local de référence `.tooling/benchmark1000-final.json` reste ignoré ;
seul le rapport agrégé synthétique est versionné. Aucun journal privé brut n'est
commité. Les tests analytiques font partie de la CI. Les seuils, pondérations,
noms finaux et consentements de partage des profils restent ouverts.
