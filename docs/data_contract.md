# Contrat de données implémenté

## Identité et sérialisation

Les stable_id sont conservés exactement, jamais recalculés à partir d'un titre.
Les modèles exposent des propriétés typées et une représentation JSON copiée
et figée récursivement à la construction. `toJson()` renvoie cette vue immuable.
Tous les champs absents, null et métadonnées éditoriales restent inchangés à
l'aller-retour. Pour éditer, construire un nouveau modèle depuis une copie.

Les enums utilisent les noms wire du contrat. Une valeur inconnue est rejetée,
y compris dans les objets désactivés. Les schémas supportés sont de version 1.
Un schéma futur nécessite un nouveau lecteur ou une migration explicite.

Les sous-objets requis sont vérifiés à la construction, les références lors
de `CatalogValidator.validate`. `CatalogLoader.load` et `loadJson` réalisent
les deux étapes et lèvent `CatalogException`. `decode` est réservé aux audits
pour inspecter un graphe invalide. Il n'est pas une preuve de jouabilité.

Les erreurs contiennent code, type d'objet, stable_id et chemin de propriété.
Un sous-objet sans ID hérite de l'ID de son propriétaire. JSON incorrect,
mauvais types, enums inconnus et erreurs de lecture ont aussi des erreurs typées.

## Compatibilité exacte avec le seed

Les références de tags du seed omettent le préfixe `tag.`. La résolution accepte
l'ID exact ou le préfixe ajouté **uniquement si cette définition existe**.
Les données et stable_id restent inchangés. Aucun tag manquant n'est créé.

`minimum_status` absent vaut ACCEPTED, seule valeur autorisée par la spec.
`schema_version` absent sur un objet est hérité du document version 1.
Les listes optionnelles absentes exposent une liste vide sans l'insérer dans
le JSON. Les métadonnées manquantes du seed exposent null (voir questions).

## Prédicats et effets

Les formes ci-dessous constituent le codec, sans évaluation de règles :

| Type de prérequis | Payload |
|---|---|
| SESSION_MODE_IN | `values`: liste non vide de face_to_face, distance, hybrid |
| CLOTHES_AT_LEAST | `target`: ACTOR/PARTNER/MUTUAL, `value`: entier >= 0 |
| PHYSICAL_STATE_IS | `value`: ID non vide |
| ACCESSORY_AVAILABLE | `accessory_id`: ID non vide |
| MEDIA_CAPABILITY_AVAILABLE | `capability_id`: ID non vide |
| TEMPORARY_MEETING_ALLOWED | aucun |
| SESSION_FLAG_IS | `flag_id`: ID non vide, `value`: booléen |

| Type d'effet | Payload |
|---|---|
| CLOTHES_DELTA | `target`: ACTOR/PARTNER/MUTUAL, `delta`: entier signé |
| SET_PHYSICAL_STATE_TEMPORARY | `value`: ID non vide |
| RESTORE_PHYSICAL_STATE_AFTER_ACTION | aucun |
| SET_SESSION_FLAG | `flag_id`: ID non vide, `value`: booléen |
| CLEAR_SESSION_FLAG | `flag_id`: ID non vide |

Les propriétés étrangères sont refusées dans les prérequis, effets et paramètres.
Aucun script, effet exécuté ou inférence de consentement n'existe ici.
Les formes non présentes dans le seed sont des conventions de sérialisation
minimales à confirmer avant utilisation du moteur.

## Paramètres et préférences

Un paramètre a exactement `values` ou `range: {min,max}`. INTEGER accepte des
entiers ou une plage croissante inclusive. ENUM et DURATION_HINT utilisent
des chaînes non vides (indications éditoriales, pas des secondes implicites).
BOOLEAN utilise des booléens. Les valeurs sont non vides et distinctes.
Les choix, visibilité et deux indicateurs de pertinence sont requis.

ONE_OF exige `one_of_group_id` ; les autres modes interdisent ce champ non null.
Un `applies_to_variant_id` doit désigner une variante de la carte concernée.
Les notes privées sont des entiers 1..20 ou null quand permis. Les dates
nécessitent un fuseau explicite et gardent leur chaîne originale au round-trip.

L'existence d'une note n'est pas une autorisation de publication. Le snapshot
ne recalcule aucune valeur et ne change pas après inversion.
