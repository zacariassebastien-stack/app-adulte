# Catalogue actif V4

Le deck de production est exclusivement `cards.v4.fr.json`, construit à partir
de `CATALOGUE_CARTES_V4.txt` et de la classification normative de
`SPECIFICATION_CARTES_NOTATION_V1.md`.

- 65 cartes actives, numérotées 001 à 065 ;
- 155 variantes/stades importés ;
- `catalog_v4_scoring.json` porte uniquement les préférences principales et
  secondaires utilisées pour le prior PA ;
- `profile_questions.v1.fr.json` porte les 17 questions et leurs mappings ;
- `catalog_v4_taxonomy.json` contient la taxonomie nécessaire au runtime.

Les catalogues V1 et V2 sont archivés dans `assets/catalog/legacy/`. Ils ne
sont pas déclarés comme assets Flutter et le chargeur normal ne sait pas les
ouvrir. `CatalogLoader.loadLegacyV3()` existe uniquement pour les audits et
tests de migration explicitement nommés.

## Archive historique V1

Contenu:
- cards.v1.fr.json : 100 CardDefinition et 128 CardVariantDefinition
- profile_elements.v1.fr.json : taxonomie de préférences dérivée du catalogue
- tags.v1.json : dictionnaire de tags
- VALIDATION.txt : contrôle structurel

Important:
Ce paquet était un SEED fonctionnel pour le moteur, pas le catalogue éditorial final.
Les 100 cartes historiques ont été structurées sans changer leur identité.
Les variantes supplémentaires des cartes ouvertes servent à valider le mécanisme d'évolution.
Les combinaisons sensibles devront rester explicitement consenties et ne doivent pas être déduites automatiquement.

Prochaine passe éditoriale:
1. enrichir les variantes réellement intéressantes;
2. affiner FAIRE/RECEVOIR par pratique;
3. dissocier les tags purement techniques des éléments de profil;
4. ajouter les textes d'instruction localisés;
5. étendre progressivement au-delà des 100 cartes.
