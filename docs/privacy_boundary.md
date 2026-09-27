# Frontière publique / privée

`PublicSessionState` et `PrivatePlayerState` seront deux DTO indépendants,
sans héritage commun exposant un état joueur complet. Ils ne sont pas encore
instanciés : les champs de session relèvent des phases suivantes.

Le futur `PublicSessionState` recevra uniquement les champs explicitement
publiables produits par une projection autorisée. Il ne contiendra ni profil,
ni UserPreference, ni CardPreferenceOverride, ni CombatValueSnapshot complet,
ni notes 1–20, ni choix cachés, ni nonce, ni médias.

`PrivatePlayerState` contiendra les données du joueur propriétaire. Les modèles
de préférences et le snapshot sont privés par défaut. `toJson()` est un codec
de persistance, **pas** une autorisation de transmission au partenaire.

Aucun mécanisme de masquage UI ne remplace la projection. Le transport futur
devra vérifier l'autorisation avant de construire chaque DTO. Les moteurs purs
ne publieront jamais directement un graphe de domaine.
