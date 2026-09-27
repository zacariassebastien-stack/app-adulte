# Couple Cards — fondations Flutter / Dart

Phases 0 et 1 uniquement. Projet Android/iOS, domaine et chargement en Dart pur,
compatibles Windows. La seule UI est une coquille de lancement.

**État : fondations vérifiées, acceptation du catalogue réel bloquée.** Les
sources V2 ont 104 erreurs référentielles. Le chargeur les refuse explicitement.
Voir [questions ouvertes](docs/open_questions.md) et [audit](docs/catalog_audit.json).

## Architecture

- `lib/app/` : coquille Flutter et adaptateur AssetBundle.
- `lib/core/` : lecture JSON stricte, copie immuable, erreurs typées.
- `lib/domain/` : définitions de contenu, enums, préférences privées et snapshot.
- `lib/data/catalog_loader/` : chargement JSON et validation référentielle.
- `lib/engines/`, `lib/features/`, `lib/sync/` : périmètres réservés, documentés.
- `test/domain/`, `test/catalog/`, `test/fixtures/` : tests et données fictives.
- `tool/audit_catalog.dart` : audit CLI avec sortie JSON et code d'échec.
- `android/`, `ios/` : projets natifs générés par Flutter.

Le domaine, les moteurs et le loader n'importent ni Flutter ni dart:ui. Un test
vérifie cette frontière. L'interface publique Dart est `lib/domain/domain.dart`.
On garde un seul package pour ces phases, sans package supplémentaire ni
sous-dossiers fonctionnels vides. Les domaines média, monétisation et réseau
ne sont pas implémentés. Aucun runner Windows spécifique n'est créé.

## Implémenté

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
La séparation future public/privé est décrite dans [la frontière de confidentialité](docs/privacy_boundary.md).

## Catalogue et références

`assets/catalog/source/` contient les neuf fichiers de l'archive, sans changement.
Seuls `cards.v2.fr.json`, `profile_elements.v1.fr.json` et `tags.v1.json` sont
embarqués comme assets. V1 et les règles éditoriales restent disponibles comme
références. La spécification intégrale est dans `docs/reference/spec_contenu_v1.md`.
`docs/source_hashes.json` atteste les SHA-256 comparés à l'archive fournie.

Aucune correction éditoriale n'a été appliquée. Les références abrégées de tags
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
dart test test/domain test/catalog
flutter test
flutter build bundle --debug --target-platform android-arm64
flutter build apk --debug
flutter run
```

Sur macOS avec Xcode : `flutter build ios --no-codesign` pour vérifier le projet
iOS, puis configurer la signature pour un appareil. L'identifiant d'application
`com.example.couple_cards` est provisoire avant publication.

Audit strict (retour **1** actuellement, retour **0** seulement si valide) :

```sh
dart run tool/audit_catalog.dart
dart run tool/audit_catalog.dart assets/catalog/source docs/catalog_audit.json
```

Les tests fondamentaux n'utilisent que l'activité fictive de dessin. Le test
réel est un audit de non-régression : il constate le rejet connu du seed,
il ne prétend pas l'accepter. Le job CI séparé `catalog-acceptance` reste rouge
tant que les données n'ont pas été corrigées. Aucun test n'est ignoré.

## Vérifications et suite

Voir [le relevé de vérification](docs/verification.md) pour les résultats locaux
et les limites de compilation native. La CI est définie mais n'a pas été
exécutée sur un serveur distant depuis cette session.

Prochaine étape : résoudre les définitions manquantes et les écarts de contrat,
obtenir un audit sans erreur, puis commencer la **phase 2** (stockage local,
migrations, repositories). Aucun moteur de partie ou fonctionnalité des phases
suivantes n'a été ajouté.
