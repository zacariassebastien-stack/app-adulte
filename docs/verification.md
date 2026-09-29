# Vérification locale — Phase 4.5, 29 septembre 2026

Validation Phase 4.5 : Flutter 3.47.5 / Dart 3.13.4 sous Windows.

| Vérification | Résultat Phase 4.5 |
|---|---|
| Baseline avant modification | 196 tests Flutter réussis |
| Format lib/test/tool | Réussi |
| `dart analyze` et `flutter analyze --no-pub` | Aucun problème |
| Tests Dart domaine/catalogue/stockage/engines/simulation/analytics | 277 réussis |
| `flutter test --no-pub` | 278 réussis, dont 82 nouveaux tests analytiques/intégration |
| Audit catalogue | 100 cartes / 134 variantes / 133 éléments de profil / 105 tags, zéro erreur |
| Régression seeds 410000–410999 | 1 000 sessions, 46 304 duels, égalité exacte de toutes les métriques métier globales et par scénario |
| Collecte synthétique | 1 318 722 événements, 1 000 sessions analysées |
| Migration SQL | Aucune ; base version 2 conservée, enveloppe événement version 2, anciennes données lisibles |

Le [contrat Phase 4.5](phase45_analytics.md) précise les cas neutres, les limites
du simulateur et les axes insuffisamment observés. Le
[rapport de régression](phase45_regression.json) contient les comparaisons et
valeurs exactes. Aucun paramètre BalanceConfig, règle moteur, contenu catalogue,
UI Phase 5, média ou réseau n'a été ajouté/modifié. La CI inclut les analytics ;
son exécution distante n'est pas revendiquée. Les limites natives ci-dessous
restent celles de la Phase 4 ; aucun nouveau build natif n'est revendiqué ici.

## Relevé conservé Phase 4 — 28 septembre 2026

Environnement : Windows, Flutter 3.47.5 / Dart 3.13.4.

| Vérification | Résultat |
|---|---|
| `dart analyze` | Réussi, aucun problème |
| `flutter analyze --no-pub` | Réussi, aucun problème |
| `dart format --output=none --set-exit-if-changed lib test tool` | Réussi, aucun changement |
| `dart test test/domain test/catalog test/storage test/engines test/simulation` | 195 tests réussis |
| `dart test test/engines` | 84 tests métier réussis |
| `dart test test/simulation` | 20 tests spécifiques réussis |
| `flutter test --no-pub` | 196 tests réussis |
| Campagne BASELINE | 10 000 sessions, 462 369 duels, 418,003 s, aucune violation d'invariant |
| Benchmarks même version | 100 sessions : 3,835 s ; 1 000 : 38,941 s |
| CANDIDATE_A | Non proposé ; baseline conservée, justification dans Phase 4 |
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
et projections public/privé. Les tests Phase 4 couvrent déterminisme, variation,
limites, bilan PA, absence de consentement, STOP neutre, épuisement, invariance
des permissions selon style, comptages et comparaisons expérimentales.
La campagne de 10 000 sessions est exécutée explicitement hors CI.

Le rapport Markdown est régénéré depuis le JSON versionné, avec les nombres de
cartes détenues et jouables séparés, distributions, seeds et probabilités.
Une erreur de comparaison entre noms abrégés de tags et identifiants `tag.*`
a été corrigée dans l'agrégation du rapport et couverte par un test ; aucune
session, règle métier ou préférence n'a été modifiée par cette correction.
Tous les 100/134/133/105 objets restent ceux du catalogue de référence.

L'analyse Flutter a été relancée avec le SDK complet après un premier échec
de la copie temporaire, dépourvue du dossier `dev`. Le résultat de la relance
est bien « No issues found ». Aucun résultat de commande échouée n'est compté
comme validation.

Les compilations natives Android/iOS ne sont pas relancées pour cette Phase 4.
Lors de la livraison initiale, le bundle Flutter avait
été compilé ; l'APK était bloqué par Java/SDK Android incomplets et iOS
nécessitait macOS/Xcode. Ces résultats historiques ne valent pas compilation
de la présente correction.

La CI vérifie désormais aussi l'acceptation du catalogue et la reproductibilité
du rapport JSON. Aucun résultat CI distant n'est revendiqué ici.
Les questions d'exécution encore ouvertes sont dans `open_questions.md` ;
un audit structurel sans erreur ne constitue pas une preuve de jouabilité.
