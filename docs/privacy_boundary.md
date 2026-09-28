# Frontière publique / privée

`PublicSessionState` et `PrivatePlayerState` sont deux DTO indépendants,
sans héritage commun exposant un état joueur complet. Leur contrat minimal de
persistance est implémenté ; la projection réseau reste une phase ultérieure.

`PublicSessionState` reçoit uniquement les champs explicitement
publiables produits par une projection autorisée. Il ne contiendra ni profil,
ni UserPreference, ni CardPreferenceOverride, ni CombatValueSnapshot complet,
ni notes 1–20, ni choix cachés, ni nonce, ni médias.

`PrivatePlayerState` contient les données du joueur propriétaire. Les modèles
de préférences et le snapshot sont privés par défaut. `toJson()` est un codec
de persistance, **pas** une autorisation de transmission au partenaire.

Aucun mécanisme de masquage UI ne remplace la projection. Le transport futur
devra vérifier l'autorisation avant de construire chaque DTO. Les moteurs purs
ne publieront jamais directement un graphe de domaine.

La Phase 3 ajoute `CompleteGameState`, `PublicState`,
`PrivatePlayerProjection` et `VisibilityProjection`, en complément du
`PrivatePlayerState` persistant de Phase 2. Par défaut, l'état public
ne contient ni mains, ni PA, ni cartes engagées non autorisées à la révélation.
Le moteur conserve séparément la liste exacte des cartes publiables et les PA ;
la présentation peut demander une révélation périodique explicite sans inventer
de valeur et sans exposer le reste de l'état privé.
