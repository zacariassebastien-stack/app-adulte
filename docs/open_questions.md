# Questions ouvertes après correction du catalogue

L'audit strict accepte maintenant 100 cartes, 134 variantes, 133 éléments de
profil et 105 tags : **zéro erreur référentielle**. Les 104 erreurs initiales
sont résolues. Voir [les décisions de correction](catalog_repair.md).
Ce résultat valide le chargement, pas un moteur d'éligibilité encore absent.

## Capacités média et accessoires — avant le moteur d'éligibilité

Le codec accepte MEDIA_CAPABILITY_AVAILABLE avec un capability_id et
ACCESSORY_AVAILABLE avec un accessory_id. Cependant, aucun registre de ces IDs,
ni leur sémantique, ni leurs prédicats d'exécution ne sont définis dans le dépôt.
Aucun prérequis arbitraire n'a donc été ajouté. Décisions encore nécessaires :

- Définir les capacités de capture, envoi, réception et appel en direct,
  ainsi que les personnes auxquelles elles s'appliquent. Les cartes photo,
  vidéo et appels devront ensuite les déclarer. Une permission système seule
  ne constitue pas une preuve de consentement.
- Définir si les variantes du jeu photographe exigent une vraie capture ou
  seulement une simulation avant de leur imposer une capacité caméra.
- Définir les accessoires nécessaires aux variantes sensorielles et de
  restriction de mouvement ; ne pas présumer qu'un objet particulier est requis.
- Pour les actions autorisées à la fois en présence et à distance, définir
  comment exprimer un prérequis média conditionné par le mode. Le codec actuel
  ne permet ni condition ni alternative de prérequis. Imposer une caméra
  inconditionnellement interdirait à tort certaines actions en présence.
- Clarifier `variant.dominate_me.restraint` en mode distance : action physique,
  consigne ou autre interprétation. Ne pas déduire cette règle du seul tag.

## Métadonnées et rôles — avant exploitation complète

- Les participants et description_key des cartes, card_id, content_version et
  instruction_key des variantes, les clés de traduction complètes et
  locale_version restent à spécifier. L'imbrication reste la source de propriété
  des variantes ; aucun rôle de participant n'est inventé.
- Les rôles de profil GENERAL/FAIRE/RECEVOIR ne sont pas ceux de l'exécution
  ACTOR/PARTNER/MUTUAL. Les définitions GENERAL_ONLY existantes sont préservées.
  Les nouveaux éléments suivent ce contrat. Le futur moteur doit préciser
  comment recueillir et vérifier les accords de chaque participant, notamment
  pour les pratiques réciproques ou avec rôles distincts.
- Les variantes de base ouvertes (dont `variant.intimate_video.base`) ne
  définissent pas un périmètre d'action précis. Leur validation structurelle
  n'autorise pas les dimensions plus sensibles des variantes spécialisées.
  Définir ce périmètre avant de les rendre jouables.

## Migration et exécution

- Décider la migration de l'historique V1 vers V2 : variantes retirées et IDs
  réutilisés avec changement de niveau/texte. Cette correction conserve tous
  les IDs présents dans le commit initial, mais ne résout pas cette migration.
- Définir les vocabulaires d'états physiques, accessoires, flags et capacités,
  puis les prédicats du moteur, avant la phase 3.
- Implémenter et tester la propagation des exclusions aux descendants, sans
  propagation positive de l'acceptation. Les tests livrés protègent les données
  et exigences ; ils ne prétendent pas tester un moteur inexistant.
