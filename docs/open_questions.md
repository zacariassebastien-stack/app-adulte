# Questions réellement ouvertes après la Phase 3

Les décisions de consentement, propagation des exclusions, rôles
FAIRE/RECEVOIR, capacités média, alternatives techniques, distance, lifecycle,
recovery et intensité sont désormais implémentées et ne sont plus ouvertes.

Restent volontairement à décider ou calibrer :

- la formule définitive du coût d'écart, son cap et tous les poids de tirage ;
  les valeurs de `BalanceConfig` sont des valeurs de travail pour la Phase 4 ;
- la répartition du coût PA d'un nouveau niveau 🌶️ entre les joueurs : le moteur
  exige un paiement explicite dont la somme couvre exactement le coût, sans
  imposer une répartition ;
- les accessoires concrets à associer aux variantes éditoriales : le moteur
  supporte A OU B et A ET B, mais le catalogue actuel ne déclare aucun
  `accessory_id`, donc aucun objet n'est inventé ;
- les variantes distantes autonomes à ajouter au contenu. En particulier,
  `variant.dominate_me.restraint` reste limitée à TOGETHER tant qu'une variante
  explicitement auto-réalisée n'est pas fournie ;
- les métadonnées éditoriales encore absentes (`description_key`, participants
  plus précis, clés de traduction et versions sur certains objets) ;
- la migration de l'historique catalogue V1 vers V2 pour les variantes retirées
  ou réinterprétées ;
- les seuils de preuve du futur profil final et les métriques de simulation,
  qui appartiennent à la Phase 4 ;
- les choix de présentation du mode discret, notamment le rythme d'affichage
  des PA, qui ne changent pas la projection de sécurité du moteur.
