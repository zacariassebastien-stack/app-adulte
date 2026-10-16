# Réconciliation V4 distant et Lots 1–6

Parents du merge : `2b1845c44a06cf20316888465e3649a0fb9f4ba4` et
`e35cf6e470b8891cdb3f1de392af59f0375ef0a9`.

Le V4 distant reste la base fonctionnelle. Les points de contact cartes sont
adaptés aux concepts, quotas et usages immuables ; les contrôleurs V4 sont
conservés et adaptés. Aucun push ni déploiement Supabase dans cette opération.

## Douze conflits résolus

| Chemin | Résolution |
|---|---|
| assets/catalog/legacy/cards.v1.fr.json | Suppression Lot 1 conservée ; aucun consommateur utile |
| assets/catalog/source/README.md | Catalogue actif de 56 concepts ; V4 source des métadonnées fonctionnelles |
| lib/data/remote/supabase_network_game_repository.dart | RPC/abonnements/révisions V4, payloads natifs usage_id |
| lib/engines/deck/session_deck_builder.dart | Suppression ; définitions de cycle encore utiles dans deck_cycle_state |
| lib/engines/engines.dart | Exports conceptuels, règles V4 utiles, aucun ancien constructeur de deck |
| lib/features/game/network_duel_screen.dart | Flows/contrôles V4, choix dynamiques et usages canoniques |
| lib/features/game/network_duel_secret_store.dart | Checkpoint privé usages/quotas/intentions et état V4 de reconnexion |
| lib/features/game/network_game_controller.dart | Base V4, points cartes adaptés ; aucune occurrence comme unité de pioche |
| lib/features/game/network_profile_learning.dart | Écriture locale atomique/idempotente conservée, usage_id et SOI |
| lib/sync/rounds/network_game.dart | DTO natifs de compromis/corruption/Recovery/exécution, snapshots conservés |
| pubspec.yaml | Blocs de dépendances distants inchangés ; assets conceptuels ajoutés |
| test/features/network_multiround_test.dart | Scénarios V4 adaptés aux concepts/usages, annulation/quota et snapshots |

## Décisions appliquées au profil et à la notation

- Questionnaire V4 : 17 questions, 30 axes, mêmes associations/rôles/zones/priors.
  Comparaison structurelle au parent distant : identique hors response_scale.
  Nouvelles réponses : 5/12/18/Exclu. Le prior composé MOST_RESTRICTIVE de Q15 reste.
- Classification explicite par action du concept dans runtime_rules.fr.json :
  classifications V4 conservées, stades correspondants conservés, exceptions
  validées appliquées. Les tags sémantiques des Lots restent hors calcul.
- Moyenne pondérée de tous les composants, principal 1, secondaire 0,5 ; arrondi
  half-up final. Aucun calcul concurrent maximum/moyenne ni premier tag.
- Veto global : tout tag exclu porté par le concept, toutes options/stades et
  directions confondus, y compris hors calcul ; indépendant des coefficients.
- 022 : PENETRER principal depuis penetration_vaginale correspondant ; DOIGTS
  secondaire ; VAGINAL hors calcul et soumis au veto. Exception propre à 022.
- P3 finale : PHOTO_MUTUELLE / VIDEO_MUTUELLE principales @ MUTUEL ; PHOTO/VIDEO
  familles non notées ; ETRE_REGARDE retiré. Pas de reconstruction FAIRE+RECEVOIR.
- 013 : TENUE seule, SOI initialisé spécifiquement depuis TENUE@FAIRE (Q05 Moi).
  TENUE@RECEVOIR ne contribue pas à la note. Le veto reste global comme validé.
  SOI est préservé distinctement pour l'apprentissage ; pas d'équivalence générale.
- Les valeurs personnalisées/apprises restent distinctes des priors initiaux.
  Les anciens 20 sans provenance certaine restent 20 ; un 20 avec source
  questionnaire et réponse UNSURE explicitement prouvée est migré vers 18.
  Aucun usage engagé ni snapshot historique n'est modifié.
- Estimation propre à la carte : modèle conservé, activation non ajoutée.
- 049–052 restent bloqués. Les modèles de tags d'accessoires V4 sont conservés,
  sans inventaire inventé ni fallback hasSextoy permissif.

## Audit des 28 commits distants

Audit de code/contrats et tests disponibles ; les lignes ci-dessous ne constituent
pas une exécution Flutter à deux appareils.

| Commit | Correction préservée ou adaptation explicite |
|---|---|
| d6664b8 | Révélation/fin de manche à deux clients et frontières privées conservées |
| e3c1ae0 | Libellés d'onboarding et sélection explicite, choix résolus avant engagement |
| d113585 | Questionnaire, profils, classifications V4 ; notation adaptée selon décisions finales |
| 79c7532 | PracticeConsent historique ne conditionne plus l'éligibilité |
| 5fe1ae5 | Métadonnées fonctionnelles de durée conservées ; piments remplacés par contrat conceptuel validé |
| 53a1191 | Progression automatique, proportions/seuils conservés sur capacités conceptuelles |
| 381513c | Contexte, présence, vêtements, contraintes techniques conservés |
| 5dc7784 | Runtime/session V4 conservés ; génération par occurrences remplacée par moteur conceptuel |
| 14b5e6c | Fin d'action, état privé et reprise réseau conservés |
| 04ec592 | Compromis simplifié à une décision finale, défausse uniquement |
| ca8df26 | Corruption proposition/réponse/exécution, nouveaux usages à l'acceptation |
| 80f1987 | Interactions et détails de main conservés, choix dynamiques |
| acf64cc | Tous composants pris en compte atomiquement ; formule remplacée par pondération validée |
| 3da31e4 | Gagnant de duel conservé après compromis |
| 421cadb | Débit des capacités des ajouts acceptés ; refus libère la réservation |
| 86bc14c | Compromis canonique partagé et privé depuis usage_id/snapshot |
| 7a83ec9 | Chaque joueur peut avancer la manche |
| 89293d0 | Définition distante de next_round conservée dans migration historique |
| 51297e7 | Orientation HYBRID et disponibilité synchronisées ; aucun biais 70/30 |
| 3d49d36 | Cycle partagé canonique, quotas réinitialisés des deux côtés |
| c938c4c | Clôture canonique, nettoyage privé et historique conservés |
| 87594c6 | Projection canonique d'exécution, construite depuis snapshot immuable |
| 40bf24f | Effets persistants canoniques, durée/cibles figées |
| d879211 | Recovery main/catalogue/défausse, identités concept/usage adaptées |
| e186164 | Recovery complétées incluses dans apprentissage, barrière des confirmations |
| 16ca4ba | Snapshots ordonnés par révision et application sérialisée |
| 02b6a8f | Origines/cibles/directions des ajouts contrôlées sur usages canoniques |
| e35cf6e | Sortie Recovery vers WAITING_NEXT et hooks canoniques conservés |

Les tests retirés sur duplication de decks, identités par occurrence, substitutions
et biais HYBRID portent sur des mécanismes volontairement remplacés. Les tests
sur piment V4 fixe/guard deviennent ceux sur choix dynamiques éligibles et plafond.
Le scénario d'accessoire en main est différé car 049–052 restent explicitement
indisponibles ; les tests purs du pool et de la compatibilité ET sont conservés.
L'annulation d'un commit engagé ne restitue plus une capacité (décision Lot 3) ;
les tests distinguent cette annulation d'une réservation non engagée.

## Progression, cycles et actions secondaires

La progression utilise les mêmes quotas projetés au plafond réel N et
virtuellement N+1, via candidateFor et les classes dynamiques (zone libre -1).
La projection n'autorise aucun choix supplémentaire avant déblocage.
Le cycle est partagé dès épuisement d'un joueur ; continuation canonique et
checkpoint du nouveau cycle synchronisés pour les deux joueurs.

Compromis : uniquement rejeu de défausse, jamais ajout d'un concept en main.
Proposition = réservation, acceptation = usage neuf et débit ; source_usage_id
et données historiques figées conservés. Corruption acceptée remplace l'action
normale. Recovery garde son exception au plafond de piment. Rejouer crée un
usage neuf ; inverser/inclure un usage engagé garde son identité.
Apprentissage après réalisation et confirmations, exactement une fois par usage,
y compris corruption et Recovery ; retry/reconnexion ne double pas les effets.

## SQL et références anciennes

Migration additive `202610150001_concept_usage_contract.sql` préparée localement,
non déployée, sans nouvelle table ; fonctions portées depuis le dernier V4.
Les 30 migrations historiques distantes gardent leurs blobs Git, les 11 locales
historiques gardent aussi leurs empreintes brutes. Scénarios SQL préparés.

52 références occurrence_id/occurrenceId sous lib sont inventoriées et justifiées
dans concept_legacy_consumers.json : types partagés de cache/local/simulation,
prototype de projection et adaptation de nom temporaire des vues existantes.
Aucune dans les DTO secondaires natifs ; quota uniquement dans le checkpoint.
La colonne SQL déployée v4_consumed_occurrences transporte des usage_id acceptés,
pas des occurrences de stock. Aucun ancien constructeur ni pondération HYBRID
n'est restauré. Les moteurs encore utilisés par prototype/simulation restent.

## Validation exécutée et limites

- 142 contrôles purs des sept outils conceptuels : réussite.
- 11 tests de raccordement profil/concepts : réussite.
- 15 tests de notation, 23 runtime V4, 33 contexte/vêtements, 36 progression/
  génération conceptuelle et 12 catalogue V4 : réussite sous Dart directement.
  Certaines suites réutilisent les contrôles conceptuels : ne pas additionner
  leurs nombres comme tests distincts.
- 63 contrôles structurels SQL, 4 contrôles d'inventaire : réussite.
- Comparaison des dépendances à origin/main : blocs strictement identiques.
- Aucun marqueur de conflit. Vérification des espaces sans anomalie nouvelle.
  Deux avertissements de ligne vide finale concernent uniquement les migrations
  historiques 202610100008/009, identiques au distant : elles restent immuables.
- Analyse Dart des moteurs/domaine/contrôleur/DTO et tests purs : aucune erreur
  propre au raccordement. L'analyse incluant Flutter reste partielle : packages
  shared_preferences, drift, sqlite3, supabase_flutter absents de la résolution
  locale ; nombreuses erreurs en cascade dans les fichiers de stockage générés.
- flutter analyze --no-pub et flutter test --no-pub tentés : bloqués par accès
  refusé au journal AppData/Roaming/.dart-tool/dart-flutter-telemetry.log.
  Aucun package installé/mis à jour, aucun contournement d'architecture.
- Tests réseau/widgets Flutter préparés et analysés autant que possible, non
  exécutés. PostgreSQL/psql/Docker locaux absents : SQL non compilé/non exécuté.
  CLI Supabase existante non utilisée pour contacter la base distante.

## Vérifications réelles restantes

Sur environnement Flutter fonctionnel : analyse complète, suites réseau/widgets,
puis checklist à deux clients (docs/concept_secondary_integration.md#checklist-courte-pour-le-pc-ensuite), notamment
retry/reconnexion, compromis, corruption, Recovery, apprentissage, vêtements,
effets, HYBRID et renouvellement commun des quotas.
Sur base de test Supabase : exécuter les scénarios SQL puis valider deux clients.
Déploiement distant seulement coordonné avec les deux clients raccordés ; ne pas
lancer la migration pendant qu'un ancien runtime utilise le contrat occurrence.
Aucun déploiement effectué ni validation à deux clients revendiquée.
