# Sources des règles V4

Le catalogue éditorial actif du jeu est `../concepts/active.fr.json` : 55 concepts.
Sa version 2 remplace les variantes anatomiques de 002/004/005 par deux stades
P2/P3 × Haut/Bas/Libre. Les variantes des fichiers source ne réactivent pas ces
anciennes présentations ; voir `docs/generic_body_regions.md`.
Ses stades, piments, zones et quotas font autorité. `runtime_rules.fr.json` associe
chaque concept à sa source numérotée `card.v4.NNN` ; les décisions P1–P6 restent
prioritaires. Le chargeur lit `cards.v4.fr.json` pour les métadonnées fonctionnelles
V4 (contexte, vêtements, durée), pas pour reconstruire un deck d'occurrences.

`catalog_v4_scoring.json`, `profile_questions.v1.fr.json` et la taxonomie V4
conservent les préférences et le questionnaire du runtime stabilisé.
Le catalogue V2 dans `../legacy/` est réservé aux audits et tests historiques.
L'ancien seed V1, sans consommateur, reste supprimé comme au Lot 1.
