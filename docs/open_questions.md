# Questions réellement ouvertes après la Phase 4

Les décisions de consentement, propagation des exclusions, rôles
FAIRE/RECEVOIR, capacités média, alternatives techniques, distance, lifecycle,
recovery et intensité sont désormais implémentées et ne sont plus ouvertes.

Restent volontairement à décider ou calibrer :

- la formule définitive du coût d'écart, son cap et tous les poids de tirage ;
  les valeurs de `BalanceConfig` restent une baseline expérimentale ; voir
  [les mesures](simulation_baseline.md), sans remplacement automatique ;
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
- les seuils de preuve, pondérations et noms du futur profil final. Le contrat
  explicite style/intensité/sources/opportunités est désormais fourni par la
  [Phase 4.5](phase45_analytics.md), mais son seuil technique de trois
  observations n'est pas une validation statistique ;
- les choix de présentation du mode discret, notamment le rythme d'affichage
  des PA, qui ne changent pas la projection de sécurité du moteur.

La Phase 4 ajoute les points à valider suivants, sans réouvrir les règles métier :

- définir la « pression significative après 8–12 duels » : passage à 50 %, à
  20 %, dépense ressentie ou autre indicateur ; les trois seuils PA sont mesurés ;
- confirmer la représentativité des probabilités de décision et des profils
  synthétiques avant tout calibrage définitif ;
- comparer des styles constants et des politiques de verrou identiques sur des
  seeds appariées pour isoler leurs effets causaux ; la baseline est descriptive ;
- étendre les scénarios aux transitions hybrides, refresh contextuels autorisés,
  décisions de rôle plus larges et variantes conditionnelles ;
- examiner les mains détenues mais partiellement jouables lorsque le contexte
  change : aucun mulligan ou assouplissement du consentement n'a été ajouté.

La Phase 4.5 laisse aussi à décider la durée de conservation du journal privé,
la protection du fichier local et l'opt-in de partage d'un futur profil. La
campagne conservée ne fournit pas d'observations de rôles FAIRE/RECEVOIR : les
axes INITIATIVE/RECEPTIVITE sont préparés et testés mais restent insuffisants sur
cette baseline. Les contrôleurs Phase 5 devront intégrer le collecteur aux
transactions état/journal et utiliser les projections, jamais le journal brut.
