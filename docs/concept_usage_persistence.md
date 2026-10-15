# Lot 3 — identité d'usage et checkpoint local

Décisions utilisateur validées après ce lot : usageId canonique partagé lorsque
nécessaire ; stockage canonique dans l'état privé/local existant, sans migration
vers Drift ; réservation sans consommation, libération avant engagement et
consommation définitive idempotente à l'engagement. Le codec Drift facultatif
ci-dessous reste un constat du Lot 3 et ne sera pas raccordé comme source
canonique. Voir [le contrat serveur du Lot 4](concept_usage_server.md).

Point de départ : `7af6cc6`. Aucun SQL, contrat réseau, écran, règle d'enchère,
compromis, corruption, Recovery ou correction HYBRID n'est modifié dans ce lot.

## Modèle retenu

Une carte en main représente le concept. Un engagement effectif crée un
`ConceptUsageSnapshot` privé et immuable. La classe ne dérive pas de
`CardRuntimeState` et ne remplace pas silencieusement `occurrenceId`.

`usage_id = usage:v1:` suivi du Base64 URL du tuple JSON
`[session_id, owner_player_id, cycle, intent_id]`.

Le tuple encodé évite les collisions de séparateurs et ne dépend ni du concept,
ni du stade, ni d'une horloge ou d'un profil. Le code qui orchestre les intentions
devra créer une clé différente pour chaque nouvel usage et garder cette même clé
sur ses retries. Le format est interne et n'est pas encore un contrat serveur.
Ce n'est ni un digest, ni une signature, ni un nouveau mécanisme anti-triche.
L'identité peut être calculée dès la réservation d'une intention ; le snapshot
est figé quand cette intention devient un usage effectivement engagé.

### Ce qui est figé et pourquoi

| Donnée | Raison |
| --- | --- |
| Session, propriétaire, cycle, clé d'intention, ID d'usage et date d'engagement | Retrouver le même engagement après retry/reprise et distinguer les usages successifs |
| `concept_id`, version de catalogue et locale | Provenance stable de la définition choisie |
| `stage_id` **ou** `variant_id` | Le contrat du Lot 1 distingue les évolutions des variantes ; aucune carte actuelle ne cumule ces deux axes |
| Zone et piment effectif | Ne pas recalculer la progression ou le modificateur de zone ultérieurement |
| Direction, acteurs et cibles résolus | Ne pas les déduire des directions ou profils actuels |
| Paramètres effectivement résolus | Conserver les choix concrets, pas des sélecteurs à relancer |
| Accessoires concrets : identifiant et libellé | Une disponibilité ou un libellé d'inventaire futur ne remplace pas le matériel sélectionné |
| Tags utiles et préférences principales | Fournir les données d'apprentissage de l'action choisie, sans recharger la taxonomie courante |
| Valeurs personnelles résolues par joueur et rôle concernés | Calculs et reconstruction sans relire les préférences actuelles |
| Entrées d'effets résolues, seulement si pertinentes | Garder les paramètres applicables à cet usage ; les compteurs d'exécution restent séparés |
| Texte de l'action déjà résolu | Pouvoir restituer ce qui a été engagé même si le texte du catalogue change ou disparaît |
| `source_usage_id`, si pertinent | Tracer une provenance historique sans recycler son identité ni sa consommation |

Les champs de choix sont des valeurs résolues. Le constructeur n'effectue pas
de choix de stade, de zone ou de matériel, et ne consulte pas le catalogue à la
relecture. Leur résolution depuis le pool du Lot 2 relève du raccordement.

### Ce qui n'est pas recopié

Le catalogue complet, les listes de variantes non choisies, l'illustration, le
titre général, les descriptions éditoriales, les flags de compatibilité et les
tables de remplacement ne sont pas dupliqués dans chaque usage. Le concept et sa
version restent des références pour ces informations de présentation.

Le profil complet, le piment global, l'inventaire et l'état vestimentaire complets,
la classe de pioche et les poids de style ne sont pas des données historiques de
l'action : on conserve leurs résultats pertinents résolus plutôt que ces états.
La capacité initiale vestimentaire est déjà figée dans le stock du cycle.

Les statuts d'exécution, réponse/acceptation, ordre dans le compromis, résultat
de duel, dépenses/gains PA effectivement appliqués et marqueurs d'apprentissage
déjà appliqué appartiennent à des résultats/événements séparés, liés à `usage_id`.
Ils ne mutent pas le snapshot. Ils devront eux aussi être persistés au raccordement ;
ce lot ne prétend pas rendre les anciens parcours idempotents en les laissant
inchangés. Le nonce et les secrets de commit/reveal sont du transport privé,
pas des paramètres de l'action historique ; le protocole actuel reste intact.

Si les règles existantes peuvent inverser cet usage, un `inverted_action`
optionnel peut contenir la contrepartie déjà résolue au moment de l'engagement.
Il porte les mêmes identités de concept/stade/variante, avec les rôles et valeurs
résolus correspondants. `reconstruct(inverted: true)` lit cette donnée figée,
sans modifier l'original ni recalculer une valeur. Cette projection ne décide
jamais si une inversion est autorisée : la règle de négociation reste externe.
Sans contrepartie figée, aucune inversion n'est reconstruite implicitement.

## Quota, retry et reprise

`ConceptUsageCheckpoint` regroupe, pour un joueur et un cycle :

- les capacités et quotas restants du stock conceptuel ;
- les snapshots d'usages indexés par leurs clés d'intention ;
- la session, le joueur et le cycle qui définissent leur portée.

`engage` recherche d'abord l'intention existante. Un retry retrouve le checkpoint
et le snapshot d'origine avant tout appel aux résolveurs, à l'horloge ou au quota,
y compris si le quota est désormais nul. Une même clé présentée pour un autre
concept échoue explicitement. Pour une intention nouvelle, les données sont
résolues une fois, le snapshot est créé, puis une utilisation du **concept** est
consommée dans le nouvel état immuable. Le stade n'a aucun compteur.

La sérialisation contient stock et usages ensemble. La relecture ne recalcule
ni les capacités depuis les vêtements actuels, ni les actions depuis le catalogue.
Elle vérifie aussi que le journal d'engagements et les quotas du checkpoint
restent cohérents. Ces vérifications portent sur le format local et la cohérence
de persistance ; aucun contrôle de client hostile n'est ajouté.

L'orchestrateur futur doit sauvegarder ce nouvel état complet avant de transmettre
une commande et réutiliser l'état sauvegardé après reprise. Le Lot 3 ne choisit
pas encore le stockage canonique du runtime réseau ni sa gestion de concurrence.
Il ne garantit pas une écriture atomique entre deux systèmes de stockage distincts.

## Persistance locale sans SQL

Inspection Drift : `SessionCards` est indexée par session/joueur/**cardId**,
sans colonne occurrence. `CombatValueSnapshots` est indexée par
session/round/joueur et ne peut pas représenter plusieurs usages de compromis
du même joueur. Aucun de ces schémas n'est modifié.

En revanche, `Rounds.stateJson` contient déjà un objet JSON opaque.
`SessionRepository.save` sérialise `PersistedRoundState.state` dans ce champ,
et `load` le relit ; `save` est transactionnel. Il est donc possible d'introduire
le nouveau checkpoint localement sans migration :

`ConceptUsageCheckpointCodec.attach` place le nouvel état sous la clé dédiée
`concept_usage_v1` et conserve les autres clés. `read` le restaure, ou retourne
null si aucun nouvel état n'est présent. Il ne convertit pas d'occurrence ancienne.
Le garde-fou média déjà existant est réutilisé à cette frontière de persistance.

**Adaptation transitoire et supprimable :** ce codec est un petit pont facultatif
vers le champ JSON local existant. Aucun producteur actuel ne l'appelle. Il sera
retiré lorsque le checkpoint de jeu canonique portera directement les usages.
Il n'existe ni façade générique ancien/nouveau modèle, ni nouveau backend de
stockage, ni deuxième voie réseau ou couche de compatibilité historique.

La reprise réseau actuelle utilise surtout `SharedPreferencesNetworkDuelSecretStore`,
pas ce repository Drift. Aucun déplacement automatique de cette persistance vers
Drift ou inversement n'est effectué. Le choix du stockage canonique et du périmètre
de sa transaction doit être validé avant le raccordement effectif.

## Carte des emplois d'occurrenceId à migrer

| Fichier / symboles | Sens actuel | Contrat cible au raccordement |
| --- | --- | --- |
| `domain/game/game_models.dart` : `CardRuntimeState`, `copyWith` | Exemplaire en main et même identité ensuite engagée ; défaut = cardId | Concept en main ; usage distinct lors de l'engagement, sans remplacer tous les IDs par un seul type |
| `engines/deck/session_deck_builder.dart` : `DeckCandidateV3`, builder, paquets, runtime | Exemplaire de variante et miroir de paquets | Stock/candidates du Lot 2 ; aucune identité d'usage à la pioche |
| `engines/lifecycle/lifecycle_engine.dart` : `lock`, `engage`, `redrawDiscard`, `exhaustDiscardAction` | Même identité pour sélectionner la main puis consommer l'action | Verrou de concept séparé des usages ; consommation du quota à l'engagement défini, résultats liés à usageId |
| `features/game/network_duel_controller.dart` : `NetworkDuelCard.identity` | occurrenceId ou cardId, donc identité ambiguë selon l'appelant | Concept pour la sélection, usage pour l'engagement ; ne pas renommer le getter globalement |
| `features/game/network_game_controller.dart` : `hand`, `toggleLock`, `selectCard`, `_refill` | Identité de l'exemplaire avant choix | Identité conceptuelle et exclusions de main du Lot 2 |
| Même contrôleur : `confirmSelection`, `_activeReveal`, `_commitment`, `_restoreCancelledChoice` | Identité d'exemplaire copiée dans les paramètres de reveal | Clé d'intention/usage persistée, snapshot résolu et transport repris sans re-résolution |
| Même contrôleur : `_restoreOrCreatePrivateState`, `_persist`, `_prepareNextRound` | Restaure mains, variantes, paquets, reveal, cycle et marqueurs | Restaurer concepts + stock + usages + transport actif ; ne pas recréer d'usage au reconnect |
| `features/game/network_duel_secret_store.dart` : `NetworkPrivateGameState` et `_deckJson`/`_deckList` | Codecs de mains, copies de variantes et reveals ; fallbacks d'IDs legacy | Nouveau checkpoint canonique à raccorder ; anciens codecs supprimables après remplacement de leurs lecteurs |
| Même fichier : `NetworkPlayedCardRecord` ; contrôleur `_capturePublicDiscards` | Historique dédoublonné par occurrence, avec seulement cardId/variantId/round | Entrées historiques par usageId et données historiques autorisées ; ne pas relire le texte/les tags actuels pour reconstruire l'action |
| `sync/protocol/network_dtos.dart` : `PrivateCardDto` | occurrenceId dans une carte privée en main | Concept en main, références d'usages séparées pour les actions |
| `sync/commit_reveal/commit_reveal.dart` : `ChoicePayload`, `ChoiceRevealDto`, `CommitRevealContract` | cardId + variantId ; occurrence dans parameters ; digest du payload et nonce | Contrat réseau versionné à valider ; payload engagé stable couvrant les données résolues publiables. Ne pas fabriquer un nouveau nonce/reveal au retry |
| `sync/rounds/network_game.dart` : `NetworkCompromiseCardDto`, offres et compromis | occurrenceId est une action avec valeur et directions, mais sans paramètres/zone/matériel complets | Référence d'usage + projection résolue autorisée ; origine/ordre/résultat restent externes au snapshot |
| `engines/corruption/corruption_engine.dart` : `ActionPromise.identity` | occurrenceId ou cardId de la défausse | Nouvel usage pour une nouvelle action effectivement engagée ; lien de provenance séparé si nécessaire |
| `sync/rounds/network_game.dart` : corruption ; `data/remote/supabase_network_game_repository.dart` : `submitCorruption`/`resolveCorruption` | L'offre transmet cardId + occurrenceId ; la résolution actuelle ne transmet même plus occurrenceId, seulement carte/source/statut/visibilité | Faire circuler le même usageId et sa résolution sans perdre les choix, ni confondre deux usages du même concept |
| Contrôleur : `recoverWith`, `resolveRecovery` ; `NetworkRecoveryDto` | occurrenceId repris d'une carte ; gain/source/réponse ; pas de snapshot complet | Usage propre et valeur résolue, réponse/statut/gain appliqué dans le résultat ; quota conceptuel commun |
| `features/game/network_profile_learning.dart` : `v3LearningDescriptor` | Recharge tags et piment éditorial courants ; reçoit occurrenceId | Tags, piment effectif, préférences principales et rôles issus de l'usage figé pour les actions acceptées |
| `engines/profile/profile_learning_engine.dart` : `LearningCardDescriptor.identity`, `HandLearningEvent` | occurrenceId ou cardId\|variantId sert aux cartes vues/jouées/verrouillées | Distinguer observations de main conceptuelle et résultats d'usage ; ne pas créer une préférence permanente par usage |
| Contrôleur : `_recordLearningForRound`, `_learningRecordedRounds`, `_resolvedLearningCard` | Dédoublonnage par round et reconstruction depuis le catalogue et la direction runtime | Résultats par usage et marqueurs d'application persistés au raccordement, sans réinterpréter les paramètres historiques |
| `sync/projection/network_visibility_projection.dart` : projection de corruption | Identité d'action publique dérivée du winner occurrence/card | Projection explicite d'un usage autorisé ; ne pas publier le checkpoint privé complet |
| `domain/round/combat_value_snapshot.dart` et `data/repositories/session_repository.dart` | Valeur figée mais liée à card/variant ; persistance limitée à un snapshot/joueur/round | Le nouveau snapshot d'usage couvre l'action ; adapter les consommateurs avant retrait de l'ancien snapshot |
| `data/repositories/event_log_repository.dart` | Aucun occurrenceId typé ; payload JSON et déduplication eventId/séquence | Garder le mécanisme d'événements ; porter usageId dans les événements concernés, distinct de eventId |

Les contrôleurs locaux `local_game_controller.dart`, `local_post_duel_controller.dart`
et `local_recovery_controller.dart` travaillent encore souvent sur cardId/variantId
et `CombatValueSnapshot`, sans occurrence explicite. Ils devront eux aussi adopter
l'identité d'usage pour les actions ; remplacer seulement les chaînes occurrenceId
dans le réseau serait incomplet.

## Serveur : besoins constatés, aucune migration créée

- Les révélations sont déjà dans `network_round_reveals.choice_payload` JSONB.
  Le transport peut contenir des données supplémentaires, mais cela ne règle pas
  leur projection ou la reconstruction aval. Le nouveau codec privé ne doit pas
  être transmis tel quel : il peut contenir des valeurs personnelles et autres
  données qui ne sont pas toutes publiables.
- `validate_network_negotiation`, version finale dans
  `202610030001_directional_occurrence_pa.sql`, reconstruit une liste fermée de
  champs pour la carte initiale du compromis. Une nouvelle version devra conserver
  l'identité et les choix résolus requis, y compris la contrepartie d'inversion,
  plutôt que perdre zone, accessoires, paramètres ou entrées d'apprentissage.
- `submit_network_corruption_offer`, version finale dans
  `202610020001_network_v3_occurrences_cycles.sql`, exige que l'occurrence proposée
  corresponde à un ancien reveal et qu'elle n'ait pas déjà été consommée. Une
  nouvelle action du concept doit avoir un nouvel usage et une provenance séparée,
  pas réutiliser cet ancien ID. `resolve_network_corruption` compare encore des
  listes de cardId et remplace les actions : il faudra aussi préserver les IDs
  d'usage et leurs snapshots pendant la résolution.
- Les fonctions `submit_network_recovery` / `resolve_network_recovery` finales
  dans `202610010002_network_v3_aba.sql` interdisent/comparent les répétitions via
  occurrenceId. Elles devront comparer les usages réellement distincts et garder
  leurs données figées, sans interdire une nouvelle utilisation autorisée du concept.
- Les commandes réseau dédupliquent déjà sur commandId et payload ; il faudra
  réutiliser la même intention et le même payload sur retry. L'identité de commande
  reste distincte de l'usage, car plusieurs commandes suivent le même usage.

Les 11 migrations existantes sont immuables. Une nouvelle migration sera
nécessaire pour ces changements de RPC au Lot 4, mais **une nouvelle table
d'usages n'est pas démontrée nécessaire** : les champs JSONB existants peuvent
potentiellement porter le contrat une fois sa projection décidée. Aucun registre
serveur de quotas ou anti-triche n'est ajouté par cette conclusion.

## Décisions à valider avant de raccorder

1. **Contrat réseau versionné et projection** : noms et emplacement de usageId,
   données visibles selon la phase et données privées. Proposition : contrat
   explicite `usage_id` et projections dédiées, plutôt que changer silencieusement
   la signification de `occurrence_id`. Le Lot 3 n'impose pas ce choix au réseau.
2. **Stockage local canonique** : réutiliser le checkpoint privé réseau actuel,
   ou faire de Drift la source canonique de reprise. Le codec local ne tranche pas
   cette architecture. Dans les deux cas, stock/usages/intentions et transport
   actif devront être sauvegardés de manière cohérente avant envoi.
3. **Raccordement du cycle de vie existant** : identifier précisément la réservation,
   l'engagement effectif et l'annulation de commit. Le moteur livré ne crée aucun
   remboursement de quota ni recyclage de snapshot ; aucune décision sur l'effet
   d'une annulation existante n'est inventée. Même vigilance pour une offre encore
   en négociation avant engagement effectif.

Ces points sont laissés à la frontière de raccordement, sans modification d'un
contrat réseau ou choix silencieux entre deux stockages.

## Nettoyage possible aux Lots 4/5 et limites

Après adoption des nouvelles RPC/DTO et du checkpoint par leurs consommateurs,
retirer les champs occurrence=action et les fallbacks legacy des codecs concernés,
la reconstruction de l'historique depuis le catalogue vivant, puis le pont
`ConceptUsageCheckpointCodec` quand sa clé transitoire n'est plus utile. Les copies
de variantes et les deux paquets restent sur la liste de retrait du Lot 2.

Ne pas supprimer en bloc `CardRuntimeState`, `CombatValueSnapshot`, `ActionPromise`,
`NetworkRecoveryDto` ou `LearningCardDescriptor` maintenant : leurs lecteurs n'ont
pas été raccordés, et certaines suppressions attendent le Lot 6. Les algorithmes
de PA, de négociation, de Recovery et d'apprentissage ne sont pas remplacés par
ce contrat de données.

## Vérifications

28 contrôles d'usage réussis via `tool/check_concept_usage.dart`, également
enregistrés dans `test/domain/concept_usage_snapshot_test.dart`. Ils couvrent les
six propriétés demandées, retry après relecture et quota nul, contrepartie figée,
persistance JSON locale sur fichier puis réouverture, codec de round existant,
résolution défaillante sans consommation, et cohérence journal/quota.

Régressions : 31 contrôles de deck et 23 contrôles catalogue réussis. Analyse
ciblée des nouveaux modèles/codecs/tests et du stock modifié : aucun problème.
Le runner habituel et l'intégration réelle Drift/SharedPreferences ne sont pas
déclarés vérifiés ; les limitations locales précédemment documentées restent
inchangées. Aucun changement de dépendances ou contournement d'architecture.

Le problème HYBRID de contexte réseau initialisé en présentiel reste consigné
pour le raccordement réseau et n'est pas traité ici.
