# Couple Cards — domaine et stockage local Flutter / Dart

## Passation actuelle — clôture du chantier catalogue

**PERSONNALISATION / APPRENTISSAGE : TERMINÉ.** Validation acceptée le
27 octobre 2026. Ce chantier est clos ; ne pas rouvrir spontanément la
calibration ni relancer de recherche de coefficients, sauf problème manifeste
observé en conditions réelles et nouveau chantier décidé avec l'utilisateur.

### Référence et reprise Git

Référence fonctionnelle actuelle validée et poussée sur `origin/main` :
`b512f9aa23f268a3ed01b84cda1aa83c11f4767a`
(`fix: align active catalog eligibility and metadata`). Elle remplace
`6c1dc2c73c2a08ba6e90e346056efb6e02a5532c` comme référence fonctionnelle de reprise.
Le commit de cette passation s'y ajoute sans changement fonctionnel.

Sur le PC de travail : vérifier le dépôt, la branche `main` et les modifications
locales, récupérer `origin/main`, puis synchroniser par avance rapide si l'arbre
le permet. Ne jamais écraser de changements locaux inconnus. Vérifier ensuite
`HEAD == origin/main` ; les fichiers suivis doivent être propres.

`tools/card_print_export/` est un outil local préexistant, non suivi et hors
périmètre : **ne jamais l'ajouter au dépôt**, ni le modifier ou le supprimer pour
nettoyer Git. Sur le mini-PC, il est la seule entrée non suivie après le push du
chantier ; son absence sur une autre machine ne constitue pas un fichier manquant
du dépôt.

### Catalogue actif et validations actuelles

**CATALOGUE ACTIF / ÉLIGIBILITÉ : TERMINÉ.** Chantier clos le 28 octobre 2026.

- 55 concepts actifs au catalogue, dont **51 non suspendus** et les quatre
  concepts sextoys **049–052 explicitement suspendus**.
- Couverture questionnaire : **51/51 concepts actifs non suspendus**, avec les
  **44 préférences nécessaires au scoring initial couvertes**.
- `031 — Frottement génital` est initialisé normalement par
  `Q01 → frotter | MUTUEL → 031`, via le mécanisme générique
  questionnaire → préférences → cartes. Il ne s'agit pas d'une exception par ID.

Les corrections ont traité l'accessibilité de cartes auparavant bloquées,
les capacités médias 044–047, les conditions de 034/048, les vêtements
asymétriques 006/007, la correspondance Q05, la cohérence éditoriale et les
métadonnées. La progression des médias distingue suggestion, exposition/intimité
explicite, puis activité sexuelle en cours.

| Contrôle du dernier chantier | Résultat |
| --- | --- |
| Tests ciblés | **268 réussites**, aucun échec |
| Suite Flutter complète locale | **1 570 réussites, 7 échecs préexistants confirmés** ; sortie 1 |
| `dart analyze` | **6 erreurs dans `tools/card_editor`, 0 warning, 28 infos** ; sortie 3 |
| `flutter analyze --no-pub` | **6 erreurs dans `tools/card_editor`, 0 warning, 28 infos** ; sortie 1 |
| Compilation Android debug | Réussie |
| `git diff --check` / `git diff --cached --check` | Propres avant commit ; index vide après commit |

**Dette préexistante connue :** les sept échecs appartiennent aux anciens
bancs/tests locaux non suivis de personnalisation. Leurs noms et messages ont été
reproduits à l'identique sur une copie propre de la base `6c1dc2c...`, complétée
par ces mêmes fichiers locaux. Les six erreurs de `tools/card_editor` ont également
été reproduites sur cette base dans les mêmes conditions d'analyse racine.
Aucune nouvelle régression identifiée dans le chantier catalogue ; ne pas
corriger cette dette dans une simple passe de validation ou de documentation.

Le rapport `docs/CATALOG_ACTIVE_AUDIT_20261028.md` reste volontairement non suivi.
Préserver les anciens rapports, simulations et bancs locaux non suivis, l'élément
`git` et les artefacts Work ; ne pas les ajouter automatiquement à Git.

### Décisions de personnalisation à conserver

Paramètres de production centralisés dans `PersonalizationConfig` :

| Paramètre | Valeur |
| --- | --- |
| choice | `0.05` |
| nonChoice | `0.025` |
| decay (`repeatDecay`) | `0.9` |
| repetition floor (`repeatFloor`) | `0.50` |

Le non-choix répété suit `nominal × max(decay^(n-1), floor)` dans son épisode
d'exposition ; les retries sont dédupliqués.

- L'appréciation officielle est séparée de l'estimation interne apprise.
- Un changement de palier est proposé au joueur, jamais appliqué silencieusement.
  Les PA restent basés sur le palier officiellement confirmé.
- `Faire confiance au jeu` active l'apprentissage comportemental ;
  `Personnaliser soi-même` le désactive.
- Une préférence faible mais persistante peut s'accumuler entre plusieurs parties.
- **Aucune stabilisation ni quantification automatique à `SESSION_CLOSED`.**
  L'expérimentation d'arrondi a été retirée car elle pouvait effacer une
  préférence réelle et augmenter les propositions négatives chez le neutre.

Correctifs intégrés dans la référence fonctionnelle :

- unlock volontaire négatif faible ; unlock forcé neutre ; événements dédupliqués ;
- Corruption : budget total conservé, réparti entre les N cartes du package ;
- Recovery : une décision, un seul signal modulé par le sacrifice ;
- tags : budget de généralisation conservé, sans multiplication par le nombre
  de tags ni boucle de propagation ;
- aucune acceptation apprise depuis une résolution post-duel provisoire ;
- Compromis : signaux prévus conservés et attribution aux rôles finaux effectifs ;
- valeur privée Recovery/Corruption retrouvée dans une réservation lorsque
  nécessaire, sans se limiter aux usages engagés et sans inventer de valeur.

### Validation antérieure de la personnalisation et limites acceptées

Checkpoint historique avant le commit de personnalisation `a988d40...` ; les résultats actuels du dépôt local figurent dans le tableau catalogue ci-dessus :

| Contrôle | Résultat |
| --- | --- |
| Suite Flutter complète | **1 498 tests réussis** |
| `dart analyze` | 0 erreur, 0 warning, 28 infos ; sortie 0 |
| `flutter analyze --no-pub` | 0 erreur, 0 warning, 28 infos ; sortie liée aux infos |
| `git diff --check` | OK |

Le cas de 2 choix positifs par partie pendant 40 parties (80 observations)
accumule désormais l'apprentissage : estimation interne à 3,5, proposition obtenue,
référence officielle toujours à 7,5. Les préférences fortes, le rejet et le
retournement de tendance ont aussi été contrôlés.

Limites volontairement acceptées : légère dérive possible du profil neutre
(environ 7,2576 en parties courtes et 6,7854 en partie longue depuis 7,5),
retournement parfois lent après saturation. Elles ne justifient pas une nouvelle
calibration à elles seules. Le joueur conserve le contrôle de ses changements
de palier.

Références conservées dans le dépôt :

- [Bilan détaillé des corrections et validations](docs/personalization_functional_validation.md).
- [Banc de validation](tool/personalization_validation.dart), à utiliser pour une
  régression justifiée, pas pour poursuivre spontanément l'optimisation.
- [Contrat de personnalisation](docs/personalization_v2.md).

### Prochain point de reprise

**VALIDATION FONCTIONNELLE ANDROID EN CONDITIONS RÉELLES**

Jouer une vraie partie sur Android et relever les problèmes effectivement
visibles ou rencontrés par le joueur. La prochaine étape est une validation
fonctionnelle réelle, pas un nouvel audit théorique ni une reprise de calibration.

Checklist de partie :

- [ ] Sélection/création des profils et état initial issu du questionnaire.
- [ ] Lancement, premières mains et cohérence des cartes proposées.
- [ ] Évolution du piment, appréciation en partie et verrouillage.
- [ ] Vêtements, cibles de l'action et confirmations vestimentaires.
- [ ] Duel, Compromis, Corruption et Recovery.
- [ ] Effets persistants/multi-tours et Silence si rencontré.
- [ ] Fin de partie, nouvelle partie et persistance du profil/apprentissage.
- [ ] Médias 044 Photo, 045 Photo mutuelle, 046 Vidéo intime et 047 Vidéo mutuelle :
      vérifier leur accessibilité dans un contexte compatible et leur blocage
      lorsque la capacité nécessaire est réellement absente.

**Contrôle appareil encore à effectuer :** les capacités médias sont raccordées
au runtime et la compilation Android réussit, mais leur détection réelle sur
appareil Android n'est pas encore validée. Ne pas confondre compilation/tests
simulés du pont natif et validation sur téléphone.

Les sections et documents historiques ci-dessous décrivent d'anciens checkpoints.
Ils restent utiles comme références techniques, mais leurs anciens compteurs de
tests, statuts de livraison ou questions de calibration ne remplacent pas cette
passation actuelle. Cette mise à jour est documentaire uniquement et ne constitue
ni un déploiement ni une nouvelle validation manuelle à deux clients.

---


**Refonte conceptuelle — Lots 1 à 5 :** le [contrat catalogue](docs/catalog/concept_contract.md)
définit les 56 concepts actifs de la [spécification consolidée](docs/specs/consolidated_concepts.fr.txt).
Le [raccordement ciblé](docs/concept_runtime_integration.md) adapte le contrôleur
réseau existant au deck conceptuel, aux choix dynamiques et aux usages immuables.
123 contrôles purs passent : catalogue 23, deck 31, usage 34, projection réseau 13,
raccordement pur 22. Les tests Flutter du contrôleur restent non exécutés avec
les dépendances locales actuelles ; ce checkpoint n'est pas une validation de
partie complète à deux clients. Les concepts sextoys 049–052 attendent un inventaire
concret portant les tags ; aucun fallback permissif n'est activé.
Le [contrat serveur](docs/concept_usage_server.md) prépare une migration JSONB
**non déployée**, sans nouvelle table ; 16 contrôles structurels passent,
scénarios SQL préparés mais non exécutés. Les parcours secondaires restent pour
le Lot 6 avant bascule coordonnée. Voir le [planning](docs/concept_cards_transition.md).
Les descriptions historiques ci-dessous ne font pas autorité sur le nouveau contrat.

Le [Lot 6 — parcours secondaires](docs/concept_secondary_integration.md) raccorde
les offres/réponses aux snapshots natifs, réservations et engagements idempotents.
L'apprentissage attend les deux Terminé et conserve un reçu privé avec son agrégat.
137 contrôles purs et 21 contrôles structurels SQL passent. Le cycle partagé
renouvelle les deux checkpoints ; les validations Flutter/SQL/deux clients ne sont pas
réalisées. Voir aussi l'[inventaire des consommateurs hérités](docs/concept_legacy_consumers.json).

Phases 0 à 4.5 et premier squelette visuel de partie. Projet Android/iOS,
domaine, stockage Drift/SQLite et moteurs de jeu purs compatibles Windows.

**État : catalogue réel accepté, zéro erreur référentielle.** Les 104 erreurs
initiales sont corrigées ; les exigences de consentement sont conservées et complétées.
Voir [questions ouvertes](docs/open_questions.md) et [audit](docs/catalog_audit.json).

## Architecture

- `lib/app/` : application Flutter et adaptateur AssetBundle.
- `lib/features/game/` : écran V1, fixtures et contrôleurs locaux qui orchestrent
  sélection, duel, enchère, corruption, Recovery, lifecycle et tirage.
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

La campagne longue est explicite et séparée des tests CI. `LocalGameController`
orchestre une boucle locale déterministe : éligibilité et variante, engagements
avec snapshots, `DuelEngine`, PA, contre-enchère et défense par `AuctionEngine`,
tentations par `CorruptionEngine`, défausse par `LifecycleEngine` et refill par
`DrawEngine`. Les règles restent dans les moteurs ; l'écran ne les recalcule pas.
Le contrat actuel de `CorruptionEngine` ne prélève pas de PA et ne change pas le
vainqueur ; il valide seulement la séquence promise et le lifecycle des cartes.
De même, `DuelEngine.inverted` conserve le snapshot engagé sans exposer encore
un modèle distinct de rôles physiques. Le prototype affiche fidèlement ces
limites au lieu d'ajouter une règle UI.

Entre deux manches, `LocalRecoveryController` délègue le seuil, l'éligibilité
catalogue, le gain, le lifecycle et l'extension mutuelle à `RecoveryEngine`.
Conformément à l'intégration Phase 3 existante, l'unique condition vient de la
défausse du joueur qui récupère. Le moteur autorise théoriquement un gain au-delà
des PA initiaux, mais le seuil de 20 % et les valeurs éditoriales `/20` limitent
le parcours normal actuel ; aucun plafond supplémentaire n'est appliqué.

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

Le deck de production charge exclusivement les 65 cartes de
`assets/catalog/source/cards.v4.fr.json`. Le questionnaire initial et le calcul
des priors PA sont pilotés par `profile_questions.v1.fr.json` et
`catalog_v4_scoring.json`. Les catalogues V1/V2 ont été déplacés sous
`assets/catalog/legacy/` et ne sont plus des assets de production. La migration
et les limites connues sont décrites dans
[`docs/catalog_v4_migration.md`](docs/catalog_v4_migration.md).

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
et [l'architecture des moteurs conservés](docs/phase3_engines.md). L'interface
reste locale : duel, enchère et corruption sont branchés aux moteurs existants,
ainsi que Recovery et extension mutuelle entre les manches, sans réseau ni
persistance de production.
