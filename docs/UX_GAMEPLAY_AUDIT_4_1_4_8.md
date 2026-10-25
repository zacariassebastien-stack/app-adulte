# Audit et validation UX — points 4.1 à 4.8

23 octobre 2026. Dépôt local `app-adulte` / package Flutter `couple_cards`.

## État initial et périmètre

- HEAD et `origin/main` vérifiés à `baf473ee9288678b2c82129afc254529fc22c1bc` (`fix: align recovery with current spice level`). Aucun reset, commit, push ou ajout à l’index.
- Aucun `AGENTS.md` trouvé dans le dépôt, ses dossiers cachés pertinents ou les répertoires parents.
- Arbre suivi initialement propre. Fichiers non suivis déjà présents : `app_screen.png`, `crash_app.txt`, `flutter_debug.txt`, `inversion_A.txt`, `inversion_A_fresh.txt`, `inversion_B_fresh.txt`, `inversion_accept_A.txt`, `inversion_accept_B.txt`, `supabase/.temp/`, `tash push -m backup local lobby fixes before sync`. Préservés.
- `tools/card_print_export/` : aucune modification.
- L’interface de partie utilisée par le lobby est `NetworkDuelScreen`. Le prototype local `GameScreen` conserve son fonctionnement ; son indicateur graphique utilise le même formateur.
- Consentement, anatomie, filtres vestimentaires, PA, enchères, compromis, calcul des égalités et plage Recovery restent fondés sur leurs moteurs existants.

## Audit initial et comportement final

| Point | Avant | Après et décision technique |
| --- | --- | --- |
| 4.1 Égalité | Les boutons de concession/abandon et le résultat étaient visibles, sans carte personnelle. Le JSON réseau `initial_duel_cards` pouvait contenir les deux cartes après la résolution initiale, y compris en égalité. | `personalDuelCard`, reconstruit depuis la révélation privée et le journal existant, est affiché par `AdaptiveCardPage`. Aucun rendu de la carte adverse. La migration filtre aussi le JSON sur le demandeur en `TIE_DECISION`. Concession et PA inchangés. |
| 4.2 Multi-tours | Les rappels utilisaient des libellés génériques « toi » / « ton partenaire ». Acteur et personne concernée étaient présents dans les effets persistants. | La personne concernée et les exécutants sont distingués. `Tu` pour le joueur local ; pseudo réel nettoyé pour l’autre ; fallback « ton partenaire ». « doit continuer » est lié aux `actorPlayerIds`, jamais déduit du gagnant ou du téléphone. Les instructions figées et les compteurs sont conservés. |
| 4.3 Notation | Le profil possédait déjà le catalogue, la roue d’appréciation et la sauvegarde par carte/action/rôle ; pas d’accès depuis la carte agrandie. | Action discrète en niveau 3 pendant le choix. Chargement de l’appréciation actuelle, sauvegarde via `CatalogProfileController.rate` et `ProfileCatalogItem.ratingKey`. Les exclusions sont explicitement préservées. Les notes de la manche sont sauvegardées dans l’état privé existant pour rester stables après reconnexion ; le profil est relu pour la manche suivante. |
| 4.4 Swipe | Le niveau 2 pouvait reprendre le suivi du fan ; le niveau 3 n’offrait pas de navigation horizontale. L’attente permettait une annulation d’engagement. | Gauche = suivante, droite = précédente, sans boucle aux extrémités. Niveau 2/3 conservé ; un mouvement horizontal dominant ne joue pas la carte. Le fan reste inchangé. L’état engagé et la phase d’envoi n’exposent aucune navigation, notation ou annulation. |
| 4.5 Piment | Le HUD affichait seulement les piments actifs en overlay et les masquait en niveau 3. | Quatre symboles permanents dans un emplacement réservé au-dessus du contenu. `v4UnlockedSpice` du snapshot réseau fournit la valeur ; Recovery n’est pas une source. `IgnorePointer` et séparation du contenu évitent l’interception et le recouvrement par l’indicateur. |
| 4.6 Vêtements | La projection demandait systématiquement les confirmations aux cibles génériques. Correct pour 006/007/012, incorrect pour les performances 008/009/010 et leurs comportements associés. Recovery n’avait pas de barrière de confirmation vestimentaire équivalente. | Résolution depuis les rôles figés : retrait/choix/changement de tenue → cibles ; mise en sous-vêtements, nudité et strip-tease → acteurs. Projection, suggestions et reconstruction utilisent cette résolution. Recovery demande le compteur réel à la personne concernée ; le propriétaire ne peut terminer avec gain avant confirmation. Le serveur vérifie l’identité, l’usage et l’idempotence. |
| 4.7 Silence | Le moteur ciblait déjà l’acteur réel, mais l’impératif figé était rédigé du point de vue du propriétaire et pouvait être trompeur sur l’autre téléphone. | Seul le texte de présentation de Silence est adapté au lecteur et au porteur réel. Le snapshot, la durée, les rôles et les effets ne sont pas réécrits. Voir l’audit détaillé ci-dessous. |
| 4.8 Questionnaire | 17 questions ; les 15 premières sans description. Certains intitulés étaient trop généraux. | 15 descriptions ajoutées ; trois intitulés précisés. Les deux descriptions existantes sont conservées. Un contrat de référence vérifie tous les champs fonctionnels hors intitulé/description. Aucun profil réinitialisé ni migré. |

### Notation : identité et engagement

La clé existante contient `profileId`, `cardId` (concept), `variantId` (action, zone ou stade), et le rôle de la direction. Aucun nouvel identifiant d’apprentissage n’est créé. La carte consultée transmet exactement son action et sa direction affichées.

La roue actuelle du profil est une roue de catégories : ses neuf choix numériques correspondent à 1,5 ; 3,5 ; 5,5 ; 7,5 ; 10 ; 13 ; 15,5 ; 18 ; 20. Le moteur arrondit les PA selon sa règle existante. Il ne s’agit pas de vingt secteurs entiers. Cette logique est réutilisée. Le secteur d’exclusion reste disponible dans le profil ; pendant la partie, les exclusions conservent leur circuit de consentement distinct dans le menu de la main.

La notation ne recharge pas les valeurs de la manche. Le snapshot privé des notes de manche est une entrée de calcul figée pour la reconstruction, pas une seconde source de préférences : le profil reste la source d’apprentissage. Les futures manches relisent cette source.

L’annulation de l’engagement a été désactivée dans le contrôleur et dans l’interface. Les anciens tests qui autorisaient le retour à la main ont été adaptés pour vérifier la conservation de la carte, de l’usage consommé et du nonce après reconnexion. L’API serveur historique d’annulation demeure pour compatibilité, mais n’est plus appelée par ce parcours client.

## Audit détaillé Silence

- Concept actif : `061` — « Silence » ; unique action `061.action`, niveau de base P2. Source catalogue : `card.v4.061`, variante `variant.v4.061.base`.
- Directions disponibles : FAIRE et RECEVOIR. Aucun stade évolutif, aucune variante MUTUEL/SOLO/SIMULTANE à inventer.
- FAIRE : l’acteur est le propriétaire de la carte. RECEVOIR : l’acteur est son partenaire. Une inversion déjà résolue suit les rôles figés de la résolution.
- Le porteur de l’effet est l’acteur, contrairement à la cible générique utilisée par de nombreuses autres actions. `_freezeAction` et `v4_advance_persistent_effects` partagent déjà cette exception pour 033/061.
- Durée : trois **actions**, et non trois tours. L’activation installe l’effet après le tick de l’action qui l’active ; les actions suivantes consomment le compteur. Plusieurs actions d’un compromis peuvent donc compter séparément. Aucun changement de tick ou de durée.
- Le moteur conserve un effet persistant et son compteur. Il n’analyse pas les sons et ne bloque pas les commandes de l’interface.
- Avant, FAIRE pouvait afficher « Garde un silence complet pendant les 3 prochaines actions… » sur un écran dont le lecteur n’était pas l’acteur. RECEVOIR pouvait afficher « ton partenaire doit garder… » alors que ce lecteur était précisément la personne concernée.
- Après, la carte de résolution et le rappel nomment le porteur réel : « Tu dois garder… » ou « Julie doit garder… », avec fallback approprié. Le rappel emploie le nombre d’actions restant dans l’effet canonique. Les instructions enregistrées et les usages restent inchangés.
- Tests : FAIRE/RECEVOIR vus par A et B, pseudos présents/absents, acteur/porteur, snapshot immuable, compteur non modifié. Les tests préexistants d’activation et de progression continuent à passer.

### Ambiguïté Silence à décider

La description du concept actif autorise explicitement une interruption pour communiquer afin de décider d’une action :

> Le silence peut uniquement être interrompu lorsque vous devez communiquer pour prendre une décision concernant une action.

La variante source décrit l’absence de parole/gémissement/bruit volontaire et précise que les commandes et validations d’interface restent disponibles, sans formuler explicitement cette même exception orale.

La mécanique réelle est un effet de trois actions ; aucun capteur ou verrou ne tranche la question des paroles autorisées. Le texte actif a été conservé. Décision éventuelle : confirmer si une discussion orale nécessaire à une décision interrompt légitimement Silence, ou si seules les validations d’interface constituent l’exception. Aucune nouvelle règle choisie ici.

## Questionnaire complet

Les IDs, l’ordre, les axes et leurs libellés, les rôles, les tags, les poids, les zones, les stratégies de fusion, les versions, l’activation et l’échelle de réponses sont inchangés.

| ID | Intitulé | Description finale | État |
| --- | --- | --- | --- |
| question.v1.01 | Câlins | Se prendre dans les bras, se rapprocher et se blottir l’un contre l’autre. | Description ajoutée |
| question.v1.02 | Baisers → **Embrasser** | Embrasser son partenaire, des baisers tendres aux baisers plus intenses. | Description ajoutée |
| question.v1.03 | Jeux de mains | Utiliser ses mains pour toucher et caresser son partenaire. | Description ajoutée |
| question.v1.04 | Jeux de bouche | Utiliser sa bouche pour embrasser, lécher ou stimuler différentes parties du corps. | Description ajoutée |
| question.v1.05 | Nudité → **Se déshabiller / changer de tenue** | Retirer des vêtements, être en sous-vêtements ou nu, faire un strip-tease ou choisir une tenue. | Description ajoutée |
| question.v1.06 | Zones intimes | Stimuler les zones intimes avec les mains ou les pieds, pratiquer le facesitting ou des jeux autour de l’éjaculation. | Description ajoutée |
| question.v1.07 | Sexe oral | Stimuler les parties génitales avec la bouche. | Description ajoutée |
| question.v1.08 | Pénétration → **Pénétration vaginale** | Pratiquer une pénétration vaginale. | Description ajoutée |
| question.v1.09 | Pratiques anales | Stimuler la zone anale, avec ou sans pénétration. | Description ajoutée |
| question.v1.10 | Plaisir en solo | Se masturber soi-même. | Description ajoutée |
| question.v1.11 | Jouets / accessoires | Utiliser des jouets intimes pour stimuler le corps. | Description ajoutée |
| question.v1.12 | Jeux physiques | Explorer les frappes, les cheveux tirés, le maintien du cou, les températures et les textures. | Description ajoutée |
| question.v1.13 | Contrôle / lâcher-prise | Donner ou suivre des ordres, imposer des positions, attacher, immobiliser, limiter les sens ou la parole, supplier ou jouer avec l’humiliation. | Description ajoutée |
| question.v1.14 | Jeux de rôle / mise en scène | Jouer un personnage, se déguiser, danser, simuler une scène ou échanger des paroles coquines. | Description ajoutée |
| question.v1.15 | Se montrer / regarder | Se montrer ou regarder son partenaire, créer des photos ou vidéos intimes, ou regarder du contenu adulte. | Description ajoutée |
| question.v1.16 | Surprise / découverte | Ne pas savoir exactement ce que mon·ma partenaire me réserve. | Conservé |
| question.v1.17 | Lieux inhabituels / prise de risque | Jouer dans un endroit inhabituel ou avec un peu de risque d’être surpris. | Conservé |

Les intitulés modifiés sont uniquement « Baisers » → « Embrasser », « Nudité » → « Se déshabiller / changer de tenue », et « Pénétration » → « Pénétration vaginale » (les associations existantes sont vaginales).

Les groupes Q6 (« Zones intimes ») et Q13 (« Contrôle / lâcher-prise ») regroupent plusieurs pratiques distinctes. Leurs descriptions rendent ces associations visibles sans scinder les questions ni redéfinir les réponses. Q16 conserve son texte existant ; ses associations incluent aussi nourriture et boisson. Si l’on souhaite évaluer séparément ces pratiques ou ces surprises, cela nécessite une décision de profilage ultérieure, hors de ce chantier rédactionnel.

## Audit transversal et migration réseau

- Sources réutilisées : consentement commun, filtrage anatomique/contextuel, usages figés, `personalDuelCard`, rôle/direction, `v4UnlockedSpice`, profil et roue existants.
- La note modifiée préserve les exclusions, les PA affichés, la main, le journal des usages et la résolution. Aucun envoi des notes privées dans le snapshot réseau.
- La reconnexion conserve la carte engagée et ses valeurs ; les annulations historiques en attente ne rouvrent pas la main.
- Les confirmations de Recovery sont liées à l’usage **et** au joueur réel. Un autre joueur ne peut pas confirmer à sa place. Le gain et la résolution ne changent pas ; leur validation attend simplement l’état vestimentaire réel.
- La migration `202610230001_gameplay_ux_confirmations.sql` normalise les joueurs attendus dans les projections d’action, répare les barrières des actions encore en `FINAL_RESOLVED` sans modifier les compteurs vestimentaires déjà enregistrés, filtre les cartes en égalité et ajoute la confirmation de vêtements Recovery. Elle ne modifie aucun profil.
- Migration préparée localement, **non appliquée**. Elle doit être appliquée à l’environnement de validation avant de tester ces garanties réseau avec deux téléphones. Aucun déploiement n’a été effectué.
- Syntaxe PostgreSQL analysée avec pglast : 11 instructions, 5 routines, aucune erreur. Aucun serveur PostgreSQL/Supabase local disponible pour exécuter la migration : la validation SQL porte sur la syntaxe et les contrats ; les tests réseau Dart utilisent le backend de test.

## Tests et validation

| Validation | Résultat final |
| --- | --- |
| Régressions UX réseau nouvelles (`--plain-name UX`) | **40/40 réussies** : égalité privée, rôles, rappels, Silence, notation, reconnexion, vêtements et Recovery, contrat SQL. |
| Composants ciblés (main, HUD, wording, questionnaire) | **62/62 réussis**. Inclut navigation 2/3, extrémités, aucun engagement horizontal, états engagés, 16 combinaisons niveau/stade du HUD, boutons utilisables et contrat questionnaire. |
| Consentement/anatomie/contexte/Recovery/durée ciblés | **177/177 réussis** sur 6 fichiers. |
| Suite Flutter complète finale (`flutter test --no-pub`) | **1 389 réussis, 0 échec**, code 0, environ 83 secondes. |
| Nouveaux tests par rapport au chantier initial | **61 scénarios ajoutés** dans les fichiers existants : 40 UX réseau et 21 composants/wording/questionnaire. Plusieurs tests existants adaptés à l’engagement définitif et aux quatre symboles. |
| `dart analyze` | Code **0**, **0 erreur, 0 avertissement**, 39 informations préexistantes. |
| `flutter analyze --no-pub` | Code **1** à cause des **39 informations préexistantes** ; **0 erreur, 0 avertissement**. La commande stricte ne sort donc pas avec un statut vert. |
| Comparaison au commit initial | Les 39 diagnostics sont **strictement identiques hors numéros de lignes** à une analyse de `HEAD` extraite dans `.tooling/ux-baseline` ; aucun diagnostic nouveau. |
| Analyse séparée `tools/card_editor` | **No issues found**. Les six erreurs historiques annoncées ne se reproduisent pas dans cet environnement. Le dossier n’a pas été modifié. |
| Migration PostgreSQL | Analyse syntaxique réussie : **11 instructions, 5 routines**. Non exécutée sur une base. |
| `git diff --check` | Code **0**, aucune erreur. |
| État Git | Voir ci-dessous ; HEAD et `origin/main` inchangés. |

Les nombres des sélections ciblées se recoupent avec la suite complète ; ils ne doivent pas être additionnés.

Les journaux de validation sont conservés dans `.tooling/ux-*.txt` (ignorés par Git). Le code et les dépendances de l’application ne dépendent pas de l’analyseur SQL installé uniquement dans `.tooling/`.

### Régressions détectées et corrigées pendant le chantier

- Débordements de petits écrans après réservation de l’espace du piment : pages de fin/cycle rendues défilables et hauteur minimale de carte adaptée.
- Retour à la main via l’annulation d’engagement et sa reconstruction : parcours supprimé côté client, régressions adaptées.
- Modification de la note pouvant devenir effective sur la main après reconnexion : snapshot privé de manche conservé, relecture différée à la manche suivante.
- Notation pouvant lever implicitement un veto de stade : ajout de la sauvegarde conservant les exclusions pour ce parcours.
- Confusion entre porteur d’un effet et acteur qui doit continuer : messages séparés et tests sur les deux lecteurs.

## Fichiers modifiés ou créés

### Modifiés

- `assets/catalog/source/profile_questions.v1.fr.json`
- `lib/data/remote/supabase_network_game_repository.dart`
- `lib/features/game/game_screen.dart`
- `lib/features/game/network_duel_screen.dart`
- `lib/features/game/network_duel_secret_store.dart`
- `lib/features/game/network_game_controller.dart`
- `lib/features/game/ui/adaptive_card_page.dart`
- `lib/features/game/ui/card_hand_surface.dart`
- `lib/features/game/ui/gameplay_hud.dart`
- `lib/features/game/ui/resolution_wording.dart`
- `lib/features/profile/catalog_profile_controller.dart`
- `lib/features/profile/radial_appreciation.dart`
- `lib/sync/rounds/network_game.dart`
- `test/features/card_hand_surface_test.dart`
- `test/features/gameplay_hud_test.dart`
- `test/features/network_multiround_test.dart`
- `test/features/resolution_wording_test.dart`
- `test/profile/v4_questionnaire_test.dart`
- `test/widget_test.dart`

### Créés

- `supabase/migrations/202610230001_gameplay_ux_confirmations.sql`
- `test/fixtures/questionnaire_functional_contract.json`
- `docs/UX_GAMEPLAY_AUDIT_4_1_4_8.md` (ce rapport)

Les tests modifiés sont listés ci-dessus dans `test/`. Les nouveaux scénarios réseau utilisent le préfixe `UX`, ce qui permet une exécution ciblée. Le contrat du questionnaire est une copie des données fonctionnelles du commit initial, excluant uniquement les champs rédactionnels.

## État Git final

- HEAD et `origin/main` : `baf473ee9288678b2c82129afc254529fc22c1bc`.
- **19 fichiers suivis modifiés**, **3 fichiers nouveaux** propres au chantier (migration, contrat questionnaire, rapport).
- **Index vide** : aucun fichier ajouté/stagé.
- Les 10 entrées non suivies initiales restent présentes, distinctes des 3 fichiers nouveaux du chantier.
- Aucun changement dans `tools/card_print_export/`, aucun changement de dépendance applicative.

Les fichiers non suivis préexistants restent présents. Aucun fichier n’est ajouté à l’index. Aucun commit, push ou reset. La validation manuelle sur deux téléphones reste à effectuer par l’utilisateur après application de la migration sur l’environnement choisi.
