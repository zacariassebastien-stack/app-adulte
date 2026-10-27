# Personnalisation — bilan final avant commit

## Référence et périmètre

Dépôt : C:/Users/zacarias/Desktop/devellopement app.
Départ mini-PC : ffe70707e9f3c974c2f465b2b833af669bb261a6, seul tools/card_print_export/ non suivi. Fetch puis avance rapide vers 9d4c7b2e17bf157dbeda6078466f85c29d2e9492 (HEAD = origin/main), sans écraser de modifications locales.

Les correctifs fonctionnels non commités sont conservés. L'expérimentation d'arrondi de fin de partie est entièrement retirée : aucun traitement terminal dans le contrôleur, aucune méthode dédiée, aucune métadonnée/reçu dédié, aucun test conservant cet arrondi. Le fichier de tests spécifique a été supprimé. Les deux tests réseau de fermeture vérifient désormais l'absence de remise à zéro et la conservation de l'estimation lors d'une fermeture/reconnexion, en mode automatique ou manuel.

Aucun fichier Supabase modifié, aucune migration ajoutée. Aucun commit, push ou déploiement. tools/card_print_export/ reste intact et non suivi.

## Fichiers de production et nature des changements

- lib/engines/profile/card_personalization_engine.dart : signaux volontaire unlock/package/Recovery/Compromis, échelles pour budgets de package, cap existant explicité, preuve signée de tags, adoption des coefficients retenus et du plancher de répétition. L'estimation continue demeure distincte de la référence confirmée.
- lib/engines/profile/v4_card_rating_engine.dart : ventilation conservée du budget de tags ; changements manuels contribuant par leur delta ; absence de réinjection lors de l'acceptation d'un palier.
- lib/features/game/network_game_controller.dart : émission aux décisions canoniques, déduplication via reçus/outbox existants, budgets Corruption divisés par N, une Recovery modulée par son sacrifice légal figé en privé, suppression des acceptations provisoires et des duplications techniques, attribution du Compromis aux rôles finaux, recherche du snapshot dans les réservations privées comme dans les usages engagés.

Déverrouillage volontaire : négatif faible .05 ; forcé : zéro. La première paire lock/unlock compte les deux décisions ; répéter la paire dans le même round/action/sens n'accumule rien.
Corruption : proposant positif faible TOTAL .025, réponse acceptée positive TOTAL .05 ou refus négatif TOTAL .10, répartis entre N cartes. Ces valeurs suivent les nouveaux coefficients centraux ; la conservation est indépendante de N.
Recovery : une seule observation du proposant, .075 + .225 × sacrifice, cap .30 ; économie inchangée ceil(1.5 × valeur personnelle). Le meilleur gain légal est figé dans les paramètres privés existants ; un vieux snapshot sans ce contexte ne fabrique pas de sacrifice.
Tags : signal précis 100%, généralisation totale 50%, ventilation primaire/secondaire 70/30 avec réallocation et division entre tags. Pas de boucle de propagation, pas de changement silencieux de référence.
Compromis : demande négative modérée sur l'original ; configuration finale acceptée positive pour les deux participants dans leurs rôles effectifs. Refus sans signal supplémentaire inventé. Choix initial préservé.

## Coefficients centraux retenus

PersonalizationConfig : choice=.05, nonChoice=.025, repeatDecay=.9, repeatFloor=.50.
Pour la n-ième répétition de non-choix dans un épisode : nominal × max(.9^(n-1), .50). Le premier compte donc intégralement ; les suivants décroissent jusqu'au plancher. Le reçu empêche qu'un retry incrémente n ; un nouvel épisode recommence à n=1. La politique de décroissance reste celle déjà testée, limitée aux non-choix répétés.
Le banc utilise désormais directement PersonalizationConfig(), sans copie indépendante des coefficients.

## Snapshot Recovery/Corruption : diagnostic reproduit

Défaut réel de production : un usage public sans valeur personnelle pouvait encore être une réservation privée, alors que l'observation arrivait avant sa réconciliation comme usage engagé. L'ancien code ne cherchait que dans les checkpoints engagés et passait null à _cardFromUsage.
La reproduction N=1 avec l'ancienne recherche seule a échoué : Null check operator used on a null value, _cardFromUsage → _recordOwnPersonalization → _observePersonalization. La recherche corrigée retrouve la réservation exacte, y compris sa résolution inversée ; aucune valeur inventée et aucun enrichissement privé du contrat public.
Les reçus sont aussi consultés avant réhydratation pour ne pas redemander une réservation déjà refusée et libérée.
Les 28 traces individuelles de l'ancien PC n'étant pas disponibles, cette reproduction attribue la classe d'échec à un trou valide de production, sans prétendre expliquer individuellement chacune des 28 anciennes interruptions.

## Validation pragmatique, sans recherche de coefficients

Le banc de l'autre PC était absent. Reconstruction minimale avec le vrai moteur : graines 270000..270199, 200 trajectoires par condition, 240 décisions, 1600 trajectoires et 384000 décisions au total. Les propositions sont observées sans adoption/refus automatique. Elles ne modifient jamais les références officielles.

| Décisions/partie | Probabilité de choix | Estimation finale moyenne | Proposition positive | Proposition négative |
|---|---|---|---|---|
| 240 | 0% | 10.5429 | 0.0% | 100.0% |
| 240 | 25% | 6.7854 | 3.5% | 0.0% |
| 240 | 50% | 3.0273 | 100.0% | 0.0% |
| 240 | 95% | 1.0004 | 100.0% | 0.0% |
| 20 | 0% | 11.0151 | 0.0% | 100.0% |
| 20 | 25% | 7.2576 | 0.0% | 7.0% |
| 20 | 50% | 3.4980 | 100.0% | 0.0% |
| 20 | 95% | 1.0008 | 100.0% | 0.0% |

Les deux résultats neutres reproduisent les ordres de grandeur expressément acceptés. Rejet et préférence forte sont appris dans le bon sens. Aucun arrondi de frontière ne compense ou n'efface l'apprentissage.
40 parties × 2 choix positifs : 80 observations, estimation finale 3.5, proposition obtenue, référence officielle toujours 7.5. 40 parties × 10 choix : estimation finale 1, proposition obtenue.
Retournement : 200 choix jusqu'à 1, puis 1000 non-choix dans un épisode ; franchissement de 7.5 après 517 observations négatives, fin 13.5429, référence officielle toujours 7.5.
Pioche : 24000 tirages par bras (48000 total), contexte favorable, 48 concepts éligibles et tous observés, minimum pondéré 241 occurrences ; Epicé 20.33/40.20/29.59/9.88%, cibles 20/40/30/10. Aucun recalibrage du tirage.
Deux parcours intégrés traversent duel → Compromis → Corruption acceptée/refusée → Recovery → fermeture explicite sans interruption technique. Ce n'est pas une reproduction des 48 anciennes sessions jusqu'à épuisement naturel.

## Tests et fichiers hors production

- test/engines/card_personalization_engine_test.dart : attentes adaptées aux coefficients et généralisation signée ; contrôle officiel, confirmation/refus, rôles, persistance.
- test/engines/personalization_signal_conservation_test.dart : budgets tags, packages N=1/2/3/5, Recovery unique/capée, absence de boucle, contradiction d'hypothèse, 80 choix persistants sur 40 parties, plancher/décroissance/retry/changement d'épisode.
- test/features/network_multiround_test.dart : unlock volontaire/forcé/répétitions ; Corruption N=1/2/3/4 acceptée/refusée et reconnexion ; Recovery avec sacrifice et sans doublon ; Compromis inversé ou non, accepté/refusé, rôles finaux ; absence d'acceptation provisoire ; parcours intégrés ; fermeture/reconnexion sans perte d'apprentissage.
- tool/personalization_validation.dart : banc minimal directement branché sur les paramètres de production.
- docs/personalization_functional_validation.md : ce rapport final remplace les bilans expérimentaux devenus obsolètes.

## Limites acceptées

La différence neutre entre parties courtes/longues est volontairement acceptée. Une proposition erronée occasionnelle reste possible et exige la confirmation du joueur. Le changement d'avis après saturation peut être lent.
Les signaux historiques déjà appliqués ne sont pas rejoués ; les reçus existants restent respectés. Les anciennes métadonnées sans preuve signée de tags ne permettent pas de reconstruire leur généralisation ; les nouveaux événements apportent cette preuve. Une Recovery ancienne sans contexte de sacrifice reste modérée. Un client sans contexte préalable d'alternatives ne fabrique pas d'acceptation volontaire.

## Commandes reproductibles

Depuis la racine du dépôt, avec les exécutables dans .tooling/flutter/bin :
- flutter test --no-pub test/engines/card_personalization_engine_test.dart test/engines/personalization_signal_conservation_test.dart
- flutter test --no-pub test/features/network_multiround_test.dart
- flutter test --no-pub
- dart run tool/personalization_validation.dart
- dart analyze --format machine
- flutter analyze --no-pub
- git diff --check

Sorties conservées localement sous .tooling/finalization-* (ignorées par Git).

## Résultats finaux et audit avant commit

- Tests moteur ciblés : 44/44, sortie 0.
- Fichier réseau complet : 341/341, sortie 0.
- Suite Flutter complète : 1498/1498, sortie 0 (3 min 31 s).
- Banc : sortie 0, résultats ci-dessus ; aucun réglage supplémentaire recherché.
- dart analyze --format machine : sortie 0, 0 erreur / 0 warning / 28 infos.
- flutter analyze --no-pub : sortie 1 car les infos sont fatales par défaut, 0 erreur / 0 warning / 28 infos.
- git diff --check : sortie 0.

Audit des trois fichiers de production, des tests et des fichiers non suivis de mission : modifications limitées aux corrections fonctionnelles validées, tests associés, coefficients/plancher centralisés, banc et documentation. Recherche dans lib/, test/ et le banc : aucune méthode, reçu, calcul ou traitement d'arrondi de fin de partie restant. Aucun fichier Supabase modifié.

Git : HEAD = origin/main = 9d4c7b2e17bf157dbeda6078466f85c29d2e9492. Cinq fichiers suivis modifiés (trois production, deux tests). Trois nouveaux fichiers de mission non suivis : ce rapport, test/engines/personalization_signal_conservation_test.dart et tool/personalization_validation.dart. tools/card_print_export/ reste la quatrième entrée non suivie, intacte. Index vide. Aucun commit/push ni déploiement.

VERDICT : PRÊT À COMMIT.
