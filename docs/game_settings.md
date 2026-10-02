# Réglages et historique local

Les réglages de jeu sont conservés dans `SharedPreferences` et ne font pas
partie de l’état public réseau. Son, vibrations et animations sont trois choix
indépendants. Le thème sélectionné s’applique immédiatement au renderer et est
restauré au prochain lancement. La luminosité reste celle du système.

Le profil privé réutilise le stockage sparse existant et présente le mode
post-partie, les préférences déjà rencontrées et les évolutions en attente. Il
n’envoie aucune valeur au partenaire.

L’historique conserve au plus dix parties terminées. Une entrée contient
uniquement la date de fin, un titre de profil humoristique et une courte phrase
déterministe basée sur le nombre de rounds. Aucun identifiant de partenaire,
PA, carte, choix, nonce, consentement ou préférence n’est sérialisé.
