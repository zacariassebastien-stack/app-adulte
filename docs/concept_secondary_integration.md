# Lot 6 — usages et parcours secondaires

Base : `a6dbaec75cf89387a9dd7f05ffa8c6bdb5e3d098`, vérifiée propre au départ.
Le runtime V4 et ses contrôleurs restent la base. Ce lot adapte les identités,
les données, la consommation et la reprise ; il ne recrée pas les moteurs métier.
État : raccordement secondaire et cycle partagé adaptés, contrôles purs réalisés. La validation Flutter/SQL/deux clients n'est pas réalisée.

## Décisions confirmées pendant ce lot

- Proposition secondaire : réservation sans consommation. Acceptation définitive :
  engagement et consommation d'une capacité. Refus/retrait avant acceptation : libération.
- Rejeu depuis la défausse : nouvel usage, nouvelle capacité consommée,
  `source_usage_id` conservé. Même usage simplement inclus/inversé : aucune seconde consommation.
- Rejeu : reprendre les données figées de l'action passée, y compris sa valeur,
  sous réserve des exclusions actuelles. Le nouvel engagement possède sa propre
  identité et date ; il ne modifie pas le journal source.
- Recovery conserve son exception existante au plafond actif de piment. Les
  autres exigences, l'orientation, le consentement et les quotas restent appliqués.
- Cycle partagé : l'épuisement d'un seul joueur suffit. Le membre qui valide la
  continuation ouvre un cycle pour les deux, sans privilège permanent PLAYER_1.
- 049–052 restent indisponibles sans inventaire concret portant les tags requis.
  Aucun nom/ID/hasSextoy ne sert à inventer une compatibilité.

## Parcours raccordés

### Compromis

Les cartes offertes sont des concepts de la main ou des usages historiques
rejouables selon quota. Le choix de stade/zone/technique d'un concept en main
passe par le sélecteur existant. Une action rejouée utilise sa résolution figée.
Le moteur d'enchère et ses valeurs/coûts/réponses ne sont pas remplacés.
Les choix offerts sont réservés ; les cartes finalement acceptées engagent leurs
usages une seule fois lors de la réconciliation canonique. Une adaptation retirant
une offre libère sa réservation, et une offre définitivement refusée ne dépense rien.
Une validation locale impossible restaure le checkpoint avant la proposition.

La carte initiale conserve son usageId. Son inversion choisit le contre-snapshot
figé, avec ses rôles et sa valeur correspondante ; le codec ne réécrit pas seulement
un champ de direction et ne relit pas le catalogue actuel.

### Corruption

Le sélecteur parcourt les usages passés du propriétaire encore rejouables avec
une capacité du concept. Le snapshot source, son stade, sa zone, sa direction,
ses paramètres et sa valeur sont conservés dans le nouveau snapshot privé.
L'acceptation consomme une capacité ; la complétion ne consomme rien de plus.
Le changement de statut conserve le snapshot. Une ancienne action initialement
engagée n'est pas réutilisée comme identité d'une nouvelle promesse.
Le runtime ne rappelle plus `CorruptionEngine.resolve` pour épuiser une ancienne
occurrence : l'objectif et les phases restent ceux des RPC existantes.

### Recovery

La proposition référence une action résolue, de la main ou de l'historique
rejouable. Elle réserve sans consommer ; l'acceptation engage l'usage. Le refus
libère la réservation. Le gain continue d'appeler `RecoveryEngine.resolve`
avec la valeur figée privée du propriétaire ; il n'est pas recalculé depuis
le profil actuel. La complétion transmet la même projection, son statut et le gain.
La règle historique de seuil et les réponses déjà exposées ne sont pas modifiées.
L'ancien `RecoveryEngine.applyLifecycle` n'est plus utilisé par le runtime réseau.

### Apprentissage après les deux Terminé

Le premier Terminé prépare seulement un lot privé de données : main réellement
projetée, cartes jouées/verrouillées, actions finales, corruption accomplie,
Recovery accompli et signaux de résistance existants. Les usages engagés sont
lus dans leurs projections figées, sans reconstruction depuis le catalogue.
La main conserve une identité de concept ; une action réalisée utilise son usageId.

L'application attend les deux `ready_next` canoniques. Si le client a manqué
la fermeture, il relit le round concerné avec la fonction `network_round_json`
existante, via `getRound`. Aucun nouvel endpoint SQL ou stockage n'est créé.
Le profil et son reçu d'événement sont sauvegardés ensemble dans l'agrégat privé
existant. Un retry ou une reconnexion retrouve ce reçu et ne rejoue pas les preuves.
Les écritures du coordinateur sont sérialisées pour éviter une concurrence avec
une personnalisation manuelle. Les formules, poids et rôles d'apprentissage restent
ceux du moteur existant. Deux usages du même concept restent deux observations ;
un même usage inclus plusieurs fois dans le résultat est dédoublonné.

Un arrêt de session avant les deux confirmations ne doit pas fabriquer une
confirmation ni appliquer prématurément l'apprentissage.

## Renouvellement du cycle partagé

Le flow de continuation existant est conservé. Le contrôleur ne renouvelle plus
son stock avant la réponse serveur. Il persiste la commande de continuation avec
le cycle de départ, puis applique le nouveau numéro canonique aux deux joueurs.
Avant l'archivage, un client reconnecté réconcilie les acceptations canoniques
encore réservées localement. Chaque client archive son journal précédent, libère
les réservations non engagées,
renouvelle ses quotas et sa main, même s'il lui restait des cartes. Un client qui
reconnecte avec l'ancien checkpoint suit le même renouvellement. Un événement
retardé portant un cycle inférieur ne rétablit pas l'ancien stock.

La RPC existante `continue_network_deck_cycle` conserve sa signature : son argument
JSON `p_adjustment` transporte désormais `{expected_cycle: n}`. Sous le verrou de
session existant, une seconde commande visant le cycle déjà renouvelé retourne
l'état canonique sans incrément supplémentaire. L'ancien contrôle PLAYER_1 est
retiré ; l'identité et l'appartenance à la session restent vérifiées. Le mode
Infini utilise cette même commande canonique, sans incrément local. Un nouveau
stock entièrement inadmissible et sans usage engagé ne provoque pas une boucle
de renouvellements automatiques.

Les scénarios Flutter préparés couvrent le renouvellement d'un pair non épuisé,
la commande du deuxième membre, le retry et les continuations concurrentes. Les
scénarios SQL préparent les mêmes contrôles d'identité de cycle. Ils ne sont pas
annoncés comme exécutés dans cet environnement.

## Persistance, reprise et confidentialité

Le même document privé/local contient le checkpoint canonique et les choix
réservés, la commande secondaire en attente et le lot d'apprentissage en attente.
Les choix réservés utilisent une enveloppe immuable réemployant le format local
de snapshot ; ils ne figurent pas dans le journal des usages engagés. Ce n'est
qu'à l'acceptation que `engage` écrit le journal, la date effective et le débit.
L'identité prévisible de l'intention reste stable entre proposition et engagement.

La commande exacte est persistée avant émission, avec son payload et son ID.
Les retries rejouent cette commande ; les réponses déjà canoniques sont
réconciliées avec le même usage. Un double clic ne peut pas expédier une commande
avant la fin de la sauvegarde. L'engagement reste définitif, sans remboursement
automatique après acceptation.

Les propositions de corruption et Recovery retirent tous les `snapshot_value`,
y compris dans `inverted_resolution`, conformément au contrat SQL existant.
Le propriétaire retrouve les valeurs dans son journal privé ; le partenaire
ne les reçoit pas. La galerie sait afficher un snapshot public sans PA inconnu.
Le compromis conserve uniquement les valeurs déjà partagées par son contrat.
Les sorties privées du cache de cartes écrivent `concept_id` et `usage_id`.
La lecture des anciens noms du cache Lot 5 reste minimale pour sa reprise.

## Nettoyage et références restantes

Retirés : codecs/constructeurs secondaires hérités, reconstruction historique des
valeurs/règles secondaires depuis le catalogue, ancien historique de DrawEngine
dans la sauvegarde réseau, appels réseau aux anciens lifecycle de défausse,
`DeckShortage`, message de substitution de piment et compteurs des deux paquets.
Le fichier `session_deck_builder.dart` disparaît ; les états de cycle encore utiles
sont dans `deck_cycle_state.dart`. Aucun ancien constructeur ou biais HYBRID ne revient.

L'inventaire [concept_legacy_consumers.json](concept_legacy_consumers.json) énumère
chaque référence `occurrence_id`/`occurrenceId` restante dans `lib/`, sa cible et
sa raison. Les noms résiduels de `CardRuntimeState`/`NetworkDuelCard` sont ceux des
types partagés avec le prototype local : concept en main, usage après engagement.
Ils ne constituent ni un deuxième quota ni une identité réseau héritée.
`LearningCardDescriptor` conserve son entrée historique pour ses consommateurs
locaux ; le runtime conceptuel utilise `conceptIdentity` et `usageId`.

Les moteurs locaux/prototypes/simulation restent de vrais consommateurs de
DrawEngine, LifecycleEngine et du catalogue source V4. Drift/SessionRepository
restent consommés par leurs parcours locaux et tests. Ils ne stockent pas le
checkpoint réseau et ne sont pas réécrits dans ce lot. La route jouable du lobby
instancie `NetworkDuelScreen` puis `NetworkGameController` ; le vieux contrôleur
`NetworkDuelController` n'y est pas instancié, mais ses tests restent consommateurs.
Les onze migrations historiques ne sont jamais nettoyées ou réécrites.

## SQL : adaptation préparée, aucun déploiement

La migration non appliquée `202610150001_concept_usage_contract.sql` est adaptée
pour qu'une source de corruption puisse venir aussi d'un compromis,
d'une corruption acceptée ou d'une Recovery acceptée antérieurs. La relation porte
sur `source_usage_id` + concept + propriétaire, jamais sur le concept seul.
Plusieurs usages d'un même concept gardent des snapshots distincts dans les JSON.
Aucune table, colonne ou autorité supplémentaire sur les valeurs privées.
La RPC de continuation est également adaptée au cycle partagé décrit ci-dessus.
Les scénarios SQL couvrent ces deux changements. Aucune migration historique
n'est modifiée ; la signature de la RPC reste inchangée, le contrat JSON change.

21 contrôles structurels passent, dont l'identité des 11 migrations historiques.
Les scénarios SQL ne sont pas exécutés : aucun PostgreSQL local disponible.
La migration reste **créée, modifiée localement, non déployée**. La lecture d'un
round fermé réutilise une fonction existante. Ne pas déployer avant validation
SQL locale puis validation coordonnée des clients, avec sauvegarde habituelle.

## Contrôles et limites

137 contrôles purs réussis : catalogue 23, deck 31, usages 34, projection réseau 13,
raccordement principal/Recovery 23, parcours secondaires/apprentissage 13.
L’audit des références anciennes passe ses quatre contrôles de couverture et de
structure ; l’inventaire détaillé est joint.
L'analyse ciblée des composants purs, du contrôleur, de l'écran et des tests
modifiés passe. Cela ne vaut pas compilation Flutter complète.

Les analyses explicites des trois fichiers dépendants de SharedPreferences et
Supabase trouvent 15 erreurs dues aux imports/types absents et un avertissement
dérivé des types Supabase inconnus. Les sept dépendances non résolues restent :
`drift`, `sqlite3`, `sqlite3_flutter_libs`, `shared_preferences`, `supabase_flutter`,
`build_runner`, `drift_dev`. Aucune installation, mise à jour ou modification du
manifeste de dépendances. Les tests Flutter sont préparés/analysés, non exécutés.
Aucune validation à deux clients ni opération distante n'est effectuée ici.

## Limites préexistantes distinctes de l'identité d'usage

Le compte vestimentaire réel de 013 est toujours enregistré dans le contexte
local existant. Aucun RPC actuel ne transporte ce résultat réel vers le contexte
privé de l'autre client. De même, ce lot ne crée pas de nouveau protocole pour
les réglages globaux déjà résolus par `applyResolvedContext`. Les effets figés
sont conservés et disponibles, mais leur synchronisation générale entre clients
ne doit pas être annoncée comme validée. Ajouter de tels échanges demande un
contrat explicite ; aucun nouvel état partagé ou RPC n'est inventé ici.
Ces limites, déjà consignées au Lot 5, restent à vérifier sur le PC et à cadrer
avant une prétention de bascule complète de production.

## Checklist courte pour le PC, ensuite

1. Vérifier les dépendances du PC, lancer l'analyse et les tests Flutter ; exécuter
   les scénarios SQL sur une base locale jetable avant toute bascule coordonnée.
2. Créer une partie à deux téléphones : mains privées de concepts uniques,
   refill par classe puis concept, aucun sextoy compatible inventé.
3. Monter le piment : débloquer un stade sur une carte déjà en main ; vérifier
   zone libre, piment réel et réutilisation d'un même stade selon le quota.
4. Jouer une enchère normale puis un compromis accepté/refusé/adapté : même
   usage initial, inversion figée, réservation libérée ou une seule consommation.
5. Proposer une corruption de défausse : refus sans débit ; acceptation avec
   nouvel usage lié, puis complétion/retry sans seconde consommation.
6. Faire une Recovery acceptée/refusée, y compris au-delà du piment actif :
   autres exclusions maintenues, PA privé absent du payload, gain figé unique.
7. Couper la connexion avant/après acceptation et avant/après réponse de RPC ;
   relancer chaque client et vérifier ID, choix, snapshot, quota et commande.
8. Appuyer sur un seul Terminé : aucun apprentissage ; deuxième Terminé : une
   application. Reconnecter et répéter les notifications : aucun doublon.
9. Changer l'orientation HYBRID : éligibilité actualisée, aucune pondération 70/30.
10. Épuiser un cycle puis continuer/changer de style/activer Infini : vérifier
    le même numéro de cycle et les quotas réinitialisés des deux côtés, même si
    l'autre joueur avait encore une main. Déclencher avec le deuxième membre,
    reconnecter l'autre, puis répéter/concurrencer la commande : un seul renouvellement.

Les décisions de cycle sont appliquées dans le code. La validation effective à
deux clients, Flutter et PostgreSQL reste à réaliser selon la checklist.
