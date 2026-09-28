# Vérification locale — correction du catalogue, 28 septembre 2026

Environnement : Windows, Flutter 3.47.5 / Dart 3.13.4.

| Vérification | Résultat |
|---|---|
| `dart analyze` | Réussi, aucun problème |
| `flutter analyze --no-pub` | Réussi, aucun problème |
| `dart format lib test tool` | 21 fichiers, aucun changement à la passe finale |
| `dart test test/domain test/catalog` | 74 tests réussis |
| `flutter test --no-pub` | 75 tests réussis |
| Audit strict régénéré | Réussi, zéro erreur, code retour 0 |
| Catalogue chargé en production | 100 cartes, 134 variantes, 133 profils, 105 tags |

Les tests vérifient l'acceptation effective, l'égalité avec l'audit versionné,
la conservation des stable_id et exigences d'origine, les parents et
l'acceptation explicite, ainsi que les exigences des variantes révisées.
Le validateur de production n'a pas été assoupli.

Les compilations natives Android/iOS ne sont pas relancées pour cette
correction de données. Lors de la livraison initiale, le bundle Flutter avait
été compilé ; l'APK était bloqué par Java/SDK Android incomplets et iOS
nécessitait macOS/Xcode. Ces résultats historiques ne valent pas compilation
de la présente correction.

La CI vérifie désormais aussi l'acceptation du catalogue et la reproductibilité
du rapport JSON. Aucun résultat CI distant n'est revendiqué ici.
Les questions d'exécution encore ouvertes sont dans `open_questions.md` ;
un audit structurel sans erreur ne constitue pas une preuve de jouabilité.
