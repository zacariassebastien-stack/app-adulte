# Lot 4 — contrat serveur d'usage et migration préparée

Référence de départ : `e3ffbcd`. Migration nouvelle :
`supabase/migrations/202610150001_concept_usage_contract.sql`.

**Créée, non déployée. Exécution PostgreSQL locale bloquée : psql/PostgreSQL,
Supabase CLI et Docker non trouvés.** Les tests SQL sont livrés mais ne sont pas
déclarés réussis. Le codec Dart est vérifié séparément. Aucun accès distant,
installation de dépendance ou modification des migrations historiques.

## Décisions désormais validées

- Le concept reste l'unité de main/stock ; usageId identifie une utilisation
  engagée précise. L'ancien occurrenceId reste uniquement dans les consommateurs
  historiques non raccordés.
- Le checkpoint usages/quotas/intentions sera porté par **l'état privé/local
  existant**. Aucune migration d'architecture vers Drift. Le codec local facultatif
  du Lot 3 ne sera pas raccordé comme source canonique ; son retrait est à prévoir
  lors du raccordement. Les schémas Drift attendent l'analyse de leurs consommateurs.
- La réservation immobilise une capacité sans consommation définitive ; son
  annulation technique avant engagement la libère. L'engagement fige l'usage et
  consomme une fois. Retry/reconnexion réutilisent cet engagement ; après engagement,
  pas de restitution automatique. Le serveur ne gère pas de registre de quotas.
  Les producteurs de réservations et leur raccordement restent au Lot 5/6.

## Inspection et choix minimal

Les actions, négociations, corruptions et Recovery sont déjà stockées en JSONB
dans les révélations et les rounds. Les commandes ont une clé idempotente et un
payload persistant. Les modifications nécessaires sont donc des remplacements
de fonctions et un changement des documents JSON : **aucune table ni colonne**.

La nouvelle migration contient 10 remplacements de fonctions existantes et trois
helpers JSON internes. Les signatures et arguments RPC restent identiques. Seul
le contenu des JSON d'action change. `p_card_ids` garde son nom d'argument SQL pour
éviter un changement de signature ; son tableau contient désormais des projections
d'usages complètes. Ce nom ne crée aucun alias cardId/usageId dans les données.

## Payload canonique partagé

```json
{
  "usage_schema_version": 1,
  "usage_id": "usage:v1:…",
  "concept_id": "045",
  "owner_player_id": "UUID du propriétaire",
  "native_direction": "FAIRE",
  "effective_direction": "FAIRE",
  "resolved_action": {
    "concept_id": "045",
    "catalog_version": 1,
    "locale": "fr-FR",
    "stage_id": "045.stage.1",
    "effective_chili": 1,
    "direction": "FAIRE",
    "actor_player_ids": ["UUID acteur"],
    "target_player_ids": ["UUID cible"],
    "parameters": {},
    "accessories": [],
    "tags": ["tag sémantique de l'action"],
    "primary_preference_ids": ["préférence éditoriale principale"],
    "effects": [],
    "action_text": "Instruction déjà résolue"
  },
  "snapshot_value": 7
}
```

`variant_id` remplace `stage_id` pour une action sans évolution. Une zone choisie
est présente sous `resolved_action.zone_id` si pertinente. Une contrepartie
résolue d'inversion peut être fournie sous `inverted_resolution`, contenant
`resolved_action` et éventuellement sa valeur figée. `source_usage_id` peut
tracer une provenance ; il ne devient jamais l'identité de la nouvelle action.

Le marqueur `usage_contract_version: 1` est ajouté au retour de `network_round_json`.
Il est distinct de l'enveloppe réseau existante `schema_version: 1`, qui reste
inchangée, et du schéma privé du checkpoint du Lot 3.

`NetworkUsageProjection` est un nouveau codec de ce format, pas un adaptateur
générique ancien/nouveau modèle. Il n'est appelé par aucun contrôleur actuel.
Sa construction depuis un snapshot exige une sélection explicite des paramètres
et effets partageables. Les clés privées non sélectionnées ne sont pas copiées.

### Frontière publique / privée conservée

| Contexte | Contenu partagé |
| --- | --- |
| Reveal du duel | Projection résolue et valeur du propriétaire déjà nécessaire au contrat de duel ; contrepartie figée si applicable |
| Carte d'enchère | Projection résolue, valeur déjà partagée dans l'offre, origine et ordre en métadonnées du compromis |
| Corruption | Projection sans valeur personnelle, provenance et états d'exécution séparés |
| Proposition et résolution Recovery | Projection sans valeur personnelle ; gain 0 avant acceptation, puis gain/réponse/achèvement selon les règles existantes |

Les tags sémantiques (pratique, zone, préférences éditoriales principales) décrivent
l'action partagée et sont déjà issus du contenu public. Ils sont conservés pour
que chaque client puisse apprendre depuis les choix historiques, sans relire un
catalogue modifié. Ce ne sont pas les observations, scores ou états privés du profil.

Le tableau complet `personal_values`, les profils, l'état d'apprentissage, les
quotas, intentions, snapshots privés et inputs de calcul non partageables ne
sont jamais des champs de cette projection. Les helpers SQL vérifient le format
public, pas la véracité de valeurs privées ni le calcul autoritaire des PA.

Le nonce, le digest et les règles de visibilité de l'adversaire restent ceux du
commit/reveal existant. Aucune nouvelle signature ou mécanique anti-triche.

## Fonctions modifiées

| Fonction | Modification ciblée |
| --- | --- |
| `submit_network_round_reveal` | Accepte le document natif d'usage et sa projection publique ; garde digest, nonce, authentification, phase et retry existants |
| `submit_network_negotiation_proposal` | Valide les projections de cartes et dédoublonne sur usageId ; conserve les calculs et règles d'offre |
| `adapt_network_negotiation` | Même contrat sur l'offre finale ; pas de calcul depuis le catalogue |
| `validate_network_negotiation` | Produit la carte initiale du compromis depuis la projection déjà enregistrée, y compris sa contrepartie figée ; conserve les dépenses et règles ABA |
| `submit_network_corruption_offer` | Conserve toutes les données résolues ; identifie le nouvel usage et vérifie la provenance antérieure via sourceUsageId, sans épuiser l'identité du concept |
| `resolve_network_corruption` | Associe les statuts aux usages enregistrés, préserve leurs snapshots et leur ordre ; ne remplace plus toute l'action par une réponse réduite |
| `submit_network_recovery` | Distingue les usages du même concept dans l'historique ; n'accepte pas de valeur personnelle dans la projection |
| `resolve_network_recovery` | Même usage et même action figée que la proposition ; met à jour uniquement les champs de résultat autorisés et les PA comme auparavant |
| `network_final_choice` | Préserve la même projection lors d'une concession à égalité et dans les anciens chemins qui appellent ce helper |
| `network_round_json` | Ajoute le marqueur du contrat ; les phases de visibilité existantes ne changent pas |

Les trois helpers `network_usage_action`, `network_usage_projection` et
`network_usage_resolution` ne créent aucun état serveur. Leur exécution est
révoquée à PUBLIC/anon/authenticated : seuls les helpers/RPC existants qui en
ont besoin les utilisent. Les privilèges des fonctions remplacées sont conservés.

`respond_network_negotiation`, `respond_network_corruption` et
`respond_network_recovery` préservent déjà leurs JSON d'action en modifiant la
réponse : aucune nouvelle définition n'est nécessaire. Même constat pour le
stockage JSONB, les commandes, les commits et l'annulation de commit existante.

Les anciennes RPC de contre-enchère/défense ne sont pas supprimées dans ce lot.
Leur helper de sélection est adapté pour conserver une action résolue ; leurs
autres anciens formats devront être retirés avec leurs derniers consommateurs.

## Idempotence et reconnexion

Les commandes restent dédupliquées par commandId, portée et payload. Le client
officiel doit garder la même intention, le même usageId, le même nonce et le même
document canonique lors d'un retry. Les lectures retrouvent les JSON persistés.

Un retry déjà enregistré retourne l'état courant avant toute réapplication des
PA ou ajout à l'historique. Une résolution de corruption ne peut pas perdre les
paramètres en réécrivant le snapshot depuis sa réponse de statut. Recovery compare
la partie immuable de sa proposition à celle de sa résolution ; gain, achèvement
et réponse restent dans les champs de résultat. Il n'existe aucun fallback depuis
le catalogue ni ID d'action synthétisé au moment de relire.

Le quota reste dans le checkpoint privé/local. Cette migration ne consomme ni ne
restitue de quota ; elle ne transforme donc pas une annulation technique en usage
engagé. Les étapes de réservation/engagement seront raccordées séparément.

## Compatibilité et retrait

Le serveur natif ne maintient pas deux formats d'action. Il n'accepte pas les
anciens alias `card_id`/`occurrence_id` dans la projection native et ne devine pas
un usage à partir d'une carte. Les DTO et contrôleurs historiques continuent
actuellement à produire leur ancien format : **le déploiement casserait ce runtime**.

Les anciennes migrations restent dans l'historique, octet pour octet. Les anciens
corps de fonctions remplacés perdent leurs hypothèses occurrence=action dans le
schéma migré. Sont éliminés des corps natifs :

- génération de secours d'une occurrence depuis round/carte ;
- reconstruction du compromis à partir de quelques champs card/variant/role ;
- projection de corruption qui perd paramètres et accessoires ;
- association des réponses de corruption par cardId ;
- interdiction d'un nouvel usage Recovery fondée sur l'identité d'exemplaire.

Après raccordement, retirer les DTO/branches occurrence, les deux paquets et
les anciens codecs de stock comme décrit aux Lots 2/3. Ne pas supprimer les
fichiers de migration historiques. L'état privé/local existant sera canonique ;
le pont Drift facultatif du Lot 3 est supprimable, sans déplacement vers Drift.

## Vérification locale et état exact

- `tool/check_network_usage.dart` : **13 contrôles de projection réussis** ;
  mêmes cas enregistrés dans `test/sync/network_usage_projection_test.dart`.
- `tool/audit_usage_migration.dart` : **16 contrôles structurels réussis**,
  dont conservation des onze empreintes historiques, absence de table/colonne,
  conservation des frontières de retry et helpers internes. Cet audit ne compile
  ni n'exécute PL/pgSQL.
- Analyse Dart ciblée : aucun problème.
- `supabase/tests/concept_usage_contract.sql` : scénarios d'intégration prêts
  pour commit/reveal, compromis avec plusieurs usages d'un même concept, inversion
  figée, corruption avec statuts désordonnés, refus/acceptation Recovery, retries
  sans double gain et concession à égalité. **Non exécutés faute de psql/PostgreSQL.**
- Le runner local a été tenté : arrêt avant toute connexion sur
  `Get-Command psql` (« psql not recognized »). Syntaxe PowerShell du runner vérifiée.

Pour une installation PostgreSQL locale déjà disponible, créer une base vide
jetable nommée `concept_usage_test*`, puis lancer :

```powershell
./tool/check_usage_server.ps1 -PsqlPath 'CHEMIN_VERS_PSQL' -Database concept_usage_test
```

Ce runner impose `127.0.0.1`, refuse un nom de base hors du préfixe de test,
n'installe rien et ne réinitialise aucune base existante. Il charge un bootstrap
auth local, toutes les migrations puis les tests transactionnels avec rollback.
Ce bootstrap ne remplace pas une validation finale sur Supabase local.

## Quand déployer

Le déploiement devient sûr seulement après :

1. exécution réussie des scénarios PostgreSQL/Supabase locaux ;
2. raccordement de tous les clients officiels aux payloads d'usage, y compris les
   parcours secondaires et leur reprise ;
3. checkpoint privé canonique usages/quotas/intentions et cycle réservation /
   engagement raccordés, avec maintien du nonce/payload sur retry ;
4. validation à deux clients puis bascule coordonnée serveur/clients, sans ancienne
   session de développement incompatible à reprendre silencieusement.

Aucun déploiement distant dans ce lot. Le problème HYBRID « contexte réseau
initialisé en présentiel » reste consigné et inchangé.
