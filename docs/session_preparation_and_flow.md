# Préparation et continuation de partie

Le parcours réseau utilise désormais une proposition d’environnement versionnée.
Le style initial est explicitement choisi par l’hôte avant la première pioche.
Sa seule source canonique reste `network_game_states.deck_style`.

- Présentiel et hybride : l’hôte configure les deux environnements ; le partenaire
  reçoit un récapitulatif et valide ou refuse.
- Distance : l’hôte choisit le mode et le style et prépare son environnement ; le
  partenaire prépare le sien et accepte les paramètres communs.
- Un refus conserve la proposition et les environnements, sans ouvrir de tour.
- Les brouillons non envoyés sont conservés localement. Les propositions,
  révisions, refus et validations sont restaurés depuis le serveur.
- Changer d’orientation en hybride ne repasse pas par la préparation initiale.

## Contrats

`register_v4_setup_accessories` partage uniquement l’inventaire d’accessoires de
chaque participant, sans transmettre ses préférences privées.
`propose_v4_session_setup` est réservé à l’hôte : mode, style, environnements,
révision attendue et identifiant de commande. `respond_v4_session_setup` porte
la révision examinée, l’accord/refus et, en distance uniquement, l’environnement
personnel du partenaire. Une réponse ancienne ne valide jamais une proposition
plus récente. L’ouverture du premier tour exige le statut `ACCEPTED`.
L’ancien RPC `submit_v4_session_setup` ne permet plus de contourner ce contrat.

Le DTO de préparation expose `style`, `status`, `revision`, et pour chaque joueur
les vêtements, accessoires sélectionnés, inventaire et indicateurs de disponibilité.

## Cycles et style

Conserver le style renouvelle le cycle existant. Une hausse d’un seul niveau est
une proposition : elle n’applique ni nouveau style ni nouveau cycle avant l’accord
de l’autre participant. Un refus laisse ces deux valeurs inchangées. Un choix
périmé n’ajoute pas un vote à une autre proposition. Les retries ne renouvellent
pas deux fois le cycle. Le DTO réseau expose proposition, auteur, révision et votes.

La continuation conserve la session et le cumul PA et renouvelle les quotas des
deux joueurs via le mécanisme existant. Le changement de style accepté réapplique
immédiatement les seuils PA existants ; à 80 PA, Soft → Épicé débloque le piment 3.
Les seuils et pondérations sont inchangés.

## Après le duel

Le résultat initial conduit directement au choix du perdant : accepter, compromis
ou corruption. Le coût initial du duel reste débité une seule fois. Le compromis
peut retenir une autre action, mais ne change pas le gagnant du duel.
Le client réseau n’expose plus les appels et panneaux de contre-enchère/défense.
Les anciens RPC renvoient `ROUND_MECHANIC_REMOVED`. Les données historiques sont
conservées ; les tours conceptuels en attente à ces anciennes étapes sont repris
au choix après duel, sans restituer ni recompter les PA déjà débités.

Migration additive : `202610180002_session_preparation_and_flow.sql`.
Tests SQL : `session_preparation_and_flow.sql`, `concept_usage_contract.sql` et
`pa_spice_progression.sql`, à exécuter sur une base locale jetable après migrations.
