# Couple Cards — domaine et stockage local Flutter / Dart

Phases 0 à 4.5 et premier squelette visuel de partie. Projet Android/iOS,
domaine, stockage Drift/SQLite et moteurs de jeu purs compatibles Windows.

**État : catalogue réel accepté, zéro erreur référentielle.** Les 104 erreurs
initiales sont corrigées ; les exigences de consentement sont conservées et complétées.
Voir [questions ouvertes](docs/open_questions.md) et [audit](docs/catalog_audit.json).

## Architecture

- `lib/app/` : application Flutter et adaptateur AssetBundle.
- `lib/features/game/` : écran statique V1 alimenté par `GameScreenData`.
- `lib/core/` : lecture JSON stricte, copie immuable, erreurs typées.
- `lib/domain/` : définitions de contenu, enums, préférences privées et snapshot.
- `lib/data/catalog_loader/` : chargement JSON et validation référentielle.
- `lib/data/local/` : schéma Drift v2, migration et garde-fou médias.
- `lib/data/repositories/` : profils, catalogue local, sessions et EventLog.
- `lib/engines/` : moteurs purs de la Phase 3, sans UI ni persistance.
- `lib/simulation/` : profils artificiels, stratégies composables, runner et mesures.
- `test/simulation/` : campagne courte déterministe, consentement et invariants.
- `lib/features/`, `lib/sync/` : périmètres réservés, documentés.
- `test/domain/`, `test/catalog/`, `test/fixtures/` : tests et données fictives.
- `tool/audit_catalog.dart` : audit CLI avec sortie JSON et code d'échec.
- `android/`, `ios/` : projets natifs générés par Flutter.

Le domaine, les moteurs et le loader n'importent ni Flutter ni dart:ui. Un test
vérifie cette frontière. L'interface publique Dart est `lib/domain/domain.dart`.
On garde un seul package pour ces phases, sans package supplémentaire ni
sous-dossiers fonctionnels vides. Les domaines média, monétisation et réseau
ne sont pas implémentés. Aucun runner Windows spécifique n'est créé.

## Implémenté

La Phase 4 exécute les vrais moteurs avec des décisions artificielles séparées.
La campagne [BASELINE](docs/simulation_baseline.md) et son
[JSON complet](docs/simulation_baseline.json) sont reproductibles. Le
[protocole](docs/phase4_simulation.md) précise les probabilités, dénominateurs,
limites et questions d'équilibrage. Aucun paramètre du moteur n'est remplacé.
Les limites de simulation ne sont jamais des règles de fin de partie.

```sh
dart run tool/simulate.dart --sessions 1 --seed 410000 --output .tooling/debug.json
dart run tool/simulate.dart --sessions 1000 --output .tooling/experiment.json
dart compile exe tool/simulate.dart -o .tooling/simulate.exe
.tooling/simulate.exe --sessions 10000 --seed 410000 --output docs/simulation_baseline.json
dart run tool/simulation_report.dart
dart test test/simulation
```

La campagne longue est explicite et séparée des tests CI. Le premier écran de
partie reste un squelette statique : aucune mécanique ni navigation complète.

Les onze modèles demandés sont immuables, avec enums et codecs sans perte :
CardDefinition, CardVariantDefinition, ProfileElementDefinition, TagDefinition,
ProfileRequirement, TechnicalRequirement, StateEffect, CardParameterDefinition,
UserPreference, CardPreferenceOverride et CombatValueSnapshot.

`CatalogLoader.load` accepte une fonction asynchrone de lecture de texte ; il
convient aux fichiers locaux comme aux assets Flutter. `loadJson` reçoit trois
chaînes JSON. Les deux valident toujours avant de retourner le catalogue.
`decode` permet l'audit d'un graphe invalide et ne doit pas alimenter un moteur.
`CatalogValidator.validate` retourne toutes les erreurs référentielles ; les
lecteurs de modèles rejettent immédiatement les erreurs de forme.

Une `CatalogException` contient des `CatalogIssue` avec code, type d'objet,
stable_id et chemin de propriété. Les IDs ne dépendent jamais des traductions.
Les particularités du seed sont explicites dans [le contrat](docs/data_contract.md).
La séparation public/privé est matérialisée par deux DTO sans héritage commun et
décrite dans [la frontière de confidentialité](docs/privacy_boundary.md).

## Stockage local

Le schéma SQLite v2 persiste les quatre états de consentement et les valeurs
GENERAL/FAIRE/RECEVOIR, les overrides, les données d'évolution indépendantes,
le catalogue versionné, les sessions/rounds reprenables, PA, niveau, style,
zones et verrouillage des cartes, snapshots de combat et EventLog ordonné.
Les checkpoints, lots d'événements et installations de catalogue sont
transactionnels. Un garde-fou rejette les médias dans évolution, historique et
EventLog. La migration v1→v2 est testée sur les quatre états de consentement.

## Catalogue et références

`assets/catalog/source/` contient les neuf fichiers du seed, dont trois corrigés.
Seuls `cards.v2.fr.json`, `profile_elements.v1.fr.json` et `tags.v1.json` sont
embarqués comme assets. V1 et les règles éditoriales restent disponibles comme
références. La spécification intégrale est dans `docs/reference/spec_contenu_v1.md`.
`docs/source_hashes.json` conserve les empreintes de l'archive initiale.
`docs/catalog_hashes.json` atteste les trois fichiers actifs corrigés.

Les corrections sont détaillées dans [le relevé éditorial](docs/catalog_repair.md). Les références abrégées de tags
sont résolues vers les définitions existantes, sans modifier les stable_id.
Aucun mécanisme ne crée silencieusement un élément ou n'assouplit le consentement.

## Commandes développeur

SDK utilisé : Flutter **3.47.5**, Dart **3.13.4**. `pubspec.lock` est versionné.
Le SDK téléchargé localement et le cache sont dans `.tooling/`, ignoré par Git.
Pour cette machine, dans PowerShell à la racine :

```powershell
$env:PATH = "$PWD\.tooling\flutter\bin;$env:PATH"
$env:PUB_CACHE = "$PWD\.tooling\pub-cache"
```

Avec Flutter installé et disponible sur PATH :

```sh
flutter pub get
dart format lib test tool
dart format --output=none --set-exit-if-changed lib test tool
dart analyze
flutter analyze
dart test test/domain test/catalog test/storage test/engines test/simulation test/analytics
flutter test
flutter build bundle --debug --target-platform android-arm64
flutter build apk --debug
flutter run
```

Sur macOS avec Xcode : `flutter build ios --no-codesign` pour vérifier le projet
iOS, puis configurer la signature pour un appareil. L'identifiant d'application
`com.example.couple_cards` est provisoire avant publication.

Audit strict (retour **0** pour le catalogue corrigé, **1** si invalide) :

```sh
dart run tool/audit_catalog.dart
dart run tool/audit_catalog.dart assets/catalog/source docs/catalog_audit.json
```

Les tests fondamentaux n'utilisent que l'activité fictive de dessin. Le test
réel vérifie l'acceptation par le chargeur de production, l'audit, les identités,
la hiérarchie et la conservation des exigences de consentement. Le job CI
`catalog-acceptance` vérifie également que l'audit versionné est à jour. Aucun
test n'est ignoré.

## Vérifications et suite

Voir [le relevé de vérification](docs/verification.md) pour les résultats locaux
et les limites de compilation native. La CI est définie mais n'a pas été
exécutée sur un serveur distant depuis cette session.

La **phase 4.5** est terminée : [contrat des événements privés et statistiques](docs/phase45_analytics.md),
[régression exacte sur 1 000 sessions](docs/phase45_regression.json).
Les 19 axes disposent de métriques descriptives, sans profils humoristiques finaux.
Voir aussi [les simulations Phase 4](docs/phase4_simulation.md)
et [l'architecture des moteurs conservés](docs/phase3_engines.md).
Aucune UI de Phase 5 n'a été ajoutée.
