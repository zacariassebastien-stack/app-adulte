# Fichiers créés

Le dépôt était vide (hors `.git`) : aucun code utilisateur n'a été remplacé.

| Ensemble | Fichiers / rôle |
|---|---|
| Configuration | `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.gitignore`, `.metadata`, `.github/workflows/ci.yml` |
| Entrée Flutter | `lib/main.dart`, `lib/app/app.dart`, `lib/app/asset_catalog.dart` |
| Erreurs / JSON | `lib/core/errors/catalog_error.dart`, `lib/core/json.dart` |
| Domaine catalogue | `lib/domain/catalog/catalog.dart`, `definitions.dart`, `enums.dart`, `parameter.dart`, `requirements.dart` |
| Domaine privé | `lib/domain/profile/preferences.dart`, `lib/domain/round/combat_value_snapshot.dart` |
| Domaine persistant | `lib/domain/profile/profile_state.dart`, `lib/domain/session/session_state.dart` |
| Exports domaine | `lib/domain/domain.dart` |
| Chargement / validation | `lib/data/catalog_loader/catalog_loader.dart`, `catalog_validator.dart` |
| SQLite / Drift | `lib/data/local/app_database.dart`, code généré et migration v1→v2 |
| Repositories | profil, catalogue local, session et EventLog dans `lib/data/repositories/` |
| Moteurs purs | éligibilité, tirage, duel, enchère, corruption, recovery, intensité et lifecycle dans `lib/engines/` |
| Simulation Phase 4 | `lib/simulation/`, `tool/simulate.dart`, `tool/simulation_report.dart`, `test/simulation/` |
| Campagne BASELINE | `docs/simulation_baseline.md`, `docs/simulation_baseline.json`, protocole `docs/phase4_simulation.md` |
| Emplacements futurs | `lib/features/README.md`, `lib/sync/README.md` |
| Tests | domaine, catalogue, stockage/migration, moteurs purs et widget sous `test/` |
| Audit | `tool/audit_catalog.dart`, `docs/catalog_audit.json`, `docs/source_hashes.json` |
| Documentation | `README.md`, `docs/open_questions.md`, `docs/data_contract.md`, `docs/privacy_boundary.md`, `docs/verification.md`, ce fichier |
| Références intactes | `docs/reference/spec_contenu_v1.md`, les neuf fichiers de `assets/catalog/source/` |
| Projets natifs | `android/` (Kotlin/Gradle/manifests/icônes), `ios/` (Swift/Xcode/plists/icônes), générés par Flutter 3.47.5 |

Les fichiers natifs sont les templates standards, sans moteur ni fonctionnalité
supplémentaire. Le test compteur et l'écran compteur générés ont été remplacés
par une coquille minimale. Les caches SDK, de compilation et IDE sont ignorés.
