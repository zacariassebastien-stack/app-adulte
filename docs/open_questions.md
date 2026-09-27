# Questions ouvertes — phases 0/1

## Bloquant : le catalogue V2 fourni est incomplet

Les sources de `assets/catalog/source/` sont conservées octet pour octet.
L'audit exécutable (`tool/audit_catalog.dart`) produit `catalog_audit.json` :
100 cartes, 134 variantes, 98 éléments de profil, 98 tags, **104 erreurs**.
Le fichier `VALIDATION_V2.json` fourni annonce zéro erreur ; cette annonce
n'inclut manifestement pas toutes les vérifications référentielles demandées.

- 93 éléments référencent un parent inexistant, soit 30 IDs parents distincts.
- 7 références de tags de variantes ne possèdent aucune définition.
- 4 ProfileRequirements de variantes ciblent des éléments absents.

Le rapport JSON contient chaque objet, son stable_id et la propriété concernée.
Le chargeur de production refuse ce catalogue. Aucune référence n'est ignorée,
aucune carte n'est supprimée et aucun consentement n'est déduit des tags.

### Décision éditoriale nécessaire

Fournir les définitions des parents manquants (hiérarchie, kind, directionality,
acceptation explicite), et des quatre éléments suivants :

- `profile.media.video.suggestive`
- `profile.media.video.nude`
- `profile.media.live.instruction`
- `profile.power.order`

Fournir également les définitions des tags suivants, dont `technical_only` :

- `tag.duration.long`
- `tag.simulation.guided`
- `tag.distance.instruction.receive`
- `tag.media.video.suggestive`
- `tag.media.video.nude`
- `tag.media.live.instruction`
- `tag.power.order`

Créer automatiquement ces éléments obligerait à choisir leurs propriétés et
la propagation des exclusions ; ce ne serait pas une correction purement
technique. Remplacer les parents par null modifierait également les règles.
Ces décisions ne sont donc pas prises dans cette mission.

## Écarts du seed par rapport au contrat cible

- Les cartes n'ont pas `participants` ni `description_key`. Les variantes
  n'ont pas `card_id`, `content_version` ni `instruction_key`. Les profils et
  tags n'ont pas toutes les clés de traduction. `locale_version` est absent.
  Le codec représente ces absences explicitement sans générer de texte ni
  inventer de participants. L'imbrication indique la carte propriétaire, mais
  ne remplace pas arbitrairement les champs absents dans les données.
- `directionality` des cartes V2 est distinct du rôle des participants. Aucun
  mapping automatique FAIRE/RECEVOIR -> ACTOR/PARTNER n'est appliqué.
- Certaines variantes ajoutent des dimensions sans ProfileRequirement
  supplémentaire (par exemple `variant.caress.sensual` et
  `variant.kiss_me.lingering`). Le validateur structurel ne peut pas décider
  quelle exigence éditoriale manque ; révision nécessaire avant un moteur
  d'éligibilité. Les combinaisons sensibles ne sont jamais autorisées par
  simple union de tags.
- Les cartes média/accessoires ne portent pas systématiquement de prérequis
  de capacité/disponibilité. Aucun prédicat n'est ajouté automatiquement.
- La V2 supprime certaines variantes V1 et réutilise parfois un ID avec un
  changement de niveau/texte ; aucune table de migration n'est fournie.
  Avant phase 2, décider quelles migrations préservent l'historique V1.

## Contrats non précisés, sans exécution en phase 1

La spécification nomme les types de TechnicalRequirement/StateEffect mais ne
définit pas tous leurs payloads ni le vocabulaire des états physiques,
accessoires, flags et capacités. Les formes de sérialisation minimales sont
documentées dans `data_contract.md`; les valeurs de ces vocabulaires restent
des IDs opaques, sans sémantique ni moteur associé. Leur registre et les
prédicats d'exécution devront être précisés avant la phase 3.

`children_order` est représenté comme une liste ordonnée d'IDs enfants directs,
sans modifier l'arbre. Aucun élément du seed ne renseigne ce champ.
`role_at_commit` utilise les rôles de notation GENERAL/FAIRE/RECEVOIR ; la
projection vers les rôles d'exécution sera explicitée avec le moteur de duel.

## Conséquence sur la livraison

Les fondations indépendantes et leurs tests peuvent être vérifiés. Le critère
« catalogue réel accepté » reste **bloqué** : le job CI `catalog-acceptance`
échoue volontairement sur les données fournies. Les tests de régression du
rapport ne doivent pas être confondus avec une acceptation du catalogue.
Après résolution, mettre à jour les sources et remplacer ces tests de rejet
par le test d'acceptation, puis régénérer le rapport avec zéro erreur.
