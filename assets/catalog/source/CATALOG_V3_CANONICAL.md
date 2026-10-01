# Catalogue V3 — contrat canonique

Ce document décrit la cible de migration. Le catalogue V2 reste la source du
runtime pendant l'étape 1 ; aucune des cartes 1–90 n'est réétiquetée ici.

## Taxonomie atomique

La source canonique est `catalog_v3_taxonomy.json` (`schema_version: 3`). Un tag
appartient à exactement une catégorie :

- `PREFERENCE` : dimension personnelle notée et utilisable pour le calcul PA ;
- `ZONE` : zone du corps, jamais notée isolément ;
- `DIRECTION` : `FAIRE`, `RECEVOIR`, `SOLO`, `MUTUEL`, `SIMULTANE`,
  `ETRE_REGARDE` ou `ETRE_ENTENDU` ;
- `MATERIEL` : ressource physique disponible, non notée ;
- `TECHNIQUE` : contrainte d'éligibilité, non notée ;
- `CONTEXTE` : contexte descriptif, non noté ;
- `SESSION_PREF` : choix effectué pour la session, non noté.

Les anciens tags monolithiques ne sont pas la structure V3. La table
`legacy_mappings` relie chaque `tag.*` et, quand il existe, son `profile.*` aux
tags atomiques. Un mapping `deprecated` sans cible est volontaire et auditable.
Cette table garantit la lecture des profils et cartes actuels pendant la
migration ; elle ne remplace pas la révision éditoriale des cartes de l'étape 2.

`PAPOUILLE` est supprimé. `DISTANCE_COMPATIBLE` n'existe pas : la distance est
compatible par défaut.

`JEU_ROLE` est une préférence générale scoreable. Les scénarios précis ne sont
pas des préférences permanentes : `profile.roleplay` migre vers `JEU_ROLE`,
tandis que les dix anciens tags de scénario restent `scenario_pending` sans
cible de préférence. `LIEU_EXPOSE` reste également une préférence personnelle
scoreable ; seul le lieu concret choisi appartient au contexte de session.

Les mappings directionnels décrivent le sens du concept : regarder et être
regardé, donner et recevoir un ordre, décider et laisser décider restent
distincts. Lorsqu'un ancien tag est réutilisé dans les deux sens, comme
`tag.clothing.partner_remove`, la direction historique de la carte fait foi et
le mapping du tag n'en invente aucune.

## PA

Seules les préférences V3 participent à la valeur personnelle. La valeur de
base est le plus haut score de préférence pertinent. Le bonus de combinaison
est 0 pour une préférence significative (score >= 12), +1 pour deux, +2 pour
trois ou plus. Il n'y a pas de plafond artificiel à 20. Les zones, directions,
matériels, contraintes techniques, contextes et préférences de session sont
exclus de ce calcul.

## Engagement et vêtements

`baseEngagementLevel` est compris entre 1 et 5. Le modificateur lié aux
vêtements s'applique seulement aux bases 1–3, avec un résultat borné à 1–5. Une
base 4 ou 5 reste inchangée.

La session conserve uniquement `removableClothingInitial` et
`removableClothingRemaining`. Une carte porte un `clothingDelta` entier ou la
valeur `ASK_PLAYER`, ainsi qu'un éventuel `minimumRemovableClothing`. Aucun
inventaire détaillé de vêtements n'est prévu.

## Distance

Une carte V3 est compatible à distance sauf si elle porte explicitement
`DISTANCE_EXCLUE`. Pendant la transition, l'audit traduit les anciens
`SESSION_MODE_IN` qui excluent `distance` en incompatibilité ; cette traduction
disparaîtra après la migration des cartes.

## Jeu de rôle

`roleplayEnabled` et `roleplayScenario` sont des données de session. Les cartes
91–100 sont listées dans `roleplay_scenario_card_ids` comme scénarios à extraire
du deck lors de l'étape 2. Elles restent dans le catalogue actif à cette étape
pour ne pas casser le runtime.

## Requirements V3

Les contraintes ne sont jamais des préférences. Le contrat typé accepte :

- `DISTANCE_EXCLUE` ;
- `requiresVideo`, `requiresRoleplay`, `requiresSurpriseParty` ;
- `requiresSextoy`, `requiresVibratingToy`, `requiresRemoteControlToy` ;
- `requiresConstraintAccessory`, `requiresOil`, `requiresLubricant` ;
- `requiresProtection`, `requiresFood`, `requiresDrink`, `requiresAlcohol` ;
- `minimumRemovableClothing`.

## Couverture inverse

`dart run tool/audit_catalog_v3.dart docs/catalog_v3_coverage.json` produit le
rapport canonique. Pour chaque tag, il donne le nombre de cartes et variantes,
les couvertures `FAIRE`, `RECEVOIR`, `SOLO`, `MUTUEL`, `SIMULTANE`, le nombre de
variantes compatibles à distance et les IDs des cartes. Les résultats sont
groupés par catégorie et `zero_coverage_tags` rend tout manque explicite.

L'audit exclut les cartes 91–100 de la couverture du deck jouable, tout en les
listant comme scénarios futurs. Les deux anciens tags techniques
`tag.duration.long` et `tag.simulation.guided` restent sans cible : leurs
informations doivent devenir des paramètres/requirements lors de l'étape 2.

## Migration éditoriale progressive

Chaque carte migrée porte un bloc `v3` et chaque variante porte sa résolution
V3 complète : `tags`, `baseEngagementLevel`, `requirements`, éventuel
`clothingDelta`, candidat de fusion et ambiguïtés. Le runtime historique peut
ainsi continuer à lire ses champs legacy sans que le calcul V3 dépende de tags
monolithiques.

Le lot 2A couvre les cartes 1–30 et leurs 41 variantes. Le lot 2B couvre les
cartes 31–60 et leurs 37 variantes. Le lot 2C couvre les cartes 61–90 et leurs
40 variantes. Les cartes 91–100 restent réservées à la future extraction des
scénarios de jeu de rôle. Les rapports détaillés sont
`docs/catalog_v3_cards_1_30.json`, `docs/catalog_v3_cards_31_60.json` et
`docs/catalog_v3_cards_61_90.json`.

Les formulations orales génériques des cartes 28, 29, 36, 37, 38 et 45 ne
portent ni `BUCCAL`, ni `LECHER`, ni `SUCER` tant que l'action ou la zone n'est
pas explicitée. Leur ambiguïté éditoriale est conservée dans le bloc `v3`.

Pour auditer une autre plage, l'outil accepte `from`, `to` et le chemin de
sortie, par exemple :
`dart run tool/audit_catalog_v3_batch.dart 31 60 docs/catalog_v3_cards_31_60.json`.

Les champs `rationalizationCandidates`, `deckRemovalCandidate` et
`sessionDataCandidate` documentent les décisions éditoriales qui devront être
traitées après la migration. Ils n'altèrent ni les règles ni le deck actuel.
