# Vérification locale — Phase 3, 28 septembre 2026

Environnement : Windows, Flutter 3.47.5 / Dart 3.13.4.

| Vérification | Résultat |
|---|---|
| `dart analyze` | Réussi, aucun problème |
| `flutter analyze --no-pub` | Réussi, aucun problème |
| `dart format --output=none --set-exit-if-changed lib test tool` | Réussi, aucun changement |
| `dart test test/domain test/catalog test/storage test/engines` | 175 tests réussis |
| `dart test test/engines` | 84 tests métier réussis |
| `flutter test --no-pub` | 176 tests réussis |
| Audit strict régénéré | Réussi, zéro erreur, code retour 0 |
| Catalogue chargé en production | 100 cartes, 134 variantes, 133 profils, 105 tags |

Les tests vérifient l'acceptation effective, l'égalité avec l'audit versionné,
la conservation des stable_id et exigences d'origine, les parents et
l'acceptation explicite, ainsi que les exigences des variantes révisées.
Le validateur de production n'a pas été assoupli. Les tests de stockage couvrent
en plus les migrations et consentements, repositories, transactions, reprise,
confidentialité, absence de médias et idempotence de l'EventLog.

Les tests Phase 3 couvrent les filtres absolus et la hiérarchie de consentement,
les rôles, conditions et médias, le tirage déterministe, les transitions de
cartes, snapshots, duel, enchères, corruption, recovery, intensité, événements
et projections public/privé. Aucun test de simulation massive Phase 4 n'existe.

Les compilations natives Android/iOS ne sont pas relancées pour cette Phase 3.
Lors de la livraison initiale, le bundle Flutter avait
été compilé ; l'APK était bloqué par Java/SDK Android incomplets et iOS
nécessitait macOS/Xcode. Ces résultats historiques ne valent pas compilation
de la présente correction.

La CI vérifie désormais aussi l'acceptation du catalogue et la reproductibilité
du rapport JSON. Aucun résultat CI distant n'est revendiqué ici.
Les questions d'exécution encore ouvertes sont dans `open_questions.md` ;
un audit structurel sans erreur ne constitue pas une preuve de jouabilité.
