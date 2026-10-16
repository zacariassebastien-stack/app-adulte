# Migration du catalogue actif vers V4

## Sources actives

Le runtime charge uniquement `assets/catalog/source/cards.v4.fr.json`. Ce
fichier contient exactement les cartes `card.v4.001` à `card.v4.065` et leurs
155 variantes/stades. Sa source éditoriale est
`assets/catalog/source/CATALOGUE_CARTES_V4.txt`; la classification des tags PA
vient de `docs/SPECIFICATION_CARTES_NOTATION_V1.md` et est matérialisée dans
`catalog_v4_scoring.json`.

## Catalogues historiques

`cards.v1.fr.json` et `cards.v2.fr.json` ont été déplacés dans
`assets/catalog/legacy/`. Ils ne sont plus déclarés dans `pubspec.yaml` et le
chargeur de production ne possède aucun fallback vers eux. Le point d'entrée
`CatalogLoader.loadLegacyV3()` est réservé aux audits et tests nommés ; il ne
participe jamais à la création d'une partie.

Les historiques existants conservent leurs anciens stable IDs. Aucune
correspondance titre-vers-carte n'est tentée et aucune ancienne carte ne
réapparaît dans le deck. Aucun mapping ancien-vers-V4 n'a été créé, car la
spécification ne fournit pas de correspondance sûre.

## Profils

Les nouveaux profils utilisent le questionnaire version 1 et l'échelle
5/12/20/Exclu. Les profils existants stockés avec 3/8/20 ne sont pas réécrits :
la politique de migration n'est pas spécifiée. Les anciennes données
`PracticeConsent` restent lisibles et sérialisables, mais sont désormais legacy
et n'interviennent plus dans l'éligibilité. `ProfilePreference.excluded` est
l'unique veto permanent du profil. STOP ou un refus ne crée aucune exclusion.

## Apprentissage propre aux cartes

Les agrégats V4 utilisent la clé profil/carte/variante/rôle effectif et sont
sérialisables séparément du profil de tags. Le prior brut et son poids restent
conservés. Le passage automatique du prior à une estimation propre n'est pas
activé : son seuil et sa méthode de combinaison font partie des décisions
produit encore ouvertes.

## Données non fournies

Le catalogue texte V4 ne fournit pas de piment canonique par variante. Le JSON
de compatibilité conserve un niveau technique provisoire signalé par
`v4.spice_unspecified=true`, afin de rester lisible par le modèle historique.
Cette valeur ne constitue pas une décision éditoriale et doit être remplacée
dès qu'une table de piment V4 est validée.
