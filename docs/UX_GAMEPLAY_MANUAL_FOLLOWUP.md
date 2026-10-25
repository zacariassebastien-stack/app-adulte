# UX 4 — corrections après validation manuelle

Date : 23 octobre 2026. Base : `baf473ee9288678b2c82129afc254529fc22c1bc`.
Les modifications locales du chantier précédent sont conservées. Aucun commit, push ou déploiement effectué.

## 1. Questionnaire

Les six demandes sont appliquées :

| Thème | Description |
| --- | --- |
| Zones intimes | Stimulation des zones intimes par différents moyens. |
| Pénétration vaginale | Aucune description ; les choix suivent le titre. |
| Plaisir en solo | Pratique ne nécessitant pas forcément la participation du partenaire. |
| Jeux physiques | Exploration tactile pouvant inclure des sensations physiques plus intenses. |
| Contrôle / lâcher-prise | Jeux autour du contrôle, de l’abandon et de la dynamique de pouvoir. |
| Se montrer / regarder | Partager et explorer son intimité avec l’autre, notamment à travers différents médias. |

L’audit des 17 questions a aussi raccourci les descriptions de contact affectueux, contact des mains, contact de la bouche, vêtements et nudité, et jeu imaginaire. Les autres descriptions restent inchangées. Les changements portent uniquement sur les textes d’aide. Le test du contrat fonctionnel vérifie les identifiants, associations et paramètres inchangés.

## 2. Mon appréciation

Le bouton porte maintenant le libellé « Mon appréciation ». Il ouvre directement la roue `RadialAppreciation`, également utilisée dans le profil. La valeur qualitative existante est préchargée et surlignée. Un toucher sur un secteur, ou un glissement suivi d’un relâchement, sauvegarde par le contrôleur de profil existant et ferme la fenêtre. Aucun appui long supplémentaire n’est nécessaire dans cette fenêtre. La roue reste accessible sur un écran de 320 × 568.

La clé d’apprentissage reprend le concept, la variante/stade et la direction de la carte affichée. Les libellés et la conversion vers l’échelle interne existante sont conservés. L’exclusion reste dans son parcours de consentement existant ; cette roue ne peut pas annuler une exclusion.

La sauvegarde ne recharge pas la main et ne recalcule pas ses valeurs, les PA ou le duel. Le test vérifie le préchargement, la sauvegarde précise, l’état réseau inchangé et les valeurs figées après reconnexion. Dès l’engagement, le bouton disparaît ; l’annulation de sélection est refusée. Le gestionnaire vérifie aussi la phase avant ouverture et avant sauvegarde.

## 3. Phrase d’action

Le générateur distingue les actions centrées sur l’acteur des actions où la cible apporte une information. Les rôles métier proviennent toujours de l’action résolue figée.

- `Zizi réalise « Retirer un vêtement ».`
- `Zezette réalise « Tirage des cheveux » sur Zizi pendant les 3 prochaines actions.`

Les formulations propres aux actions mutuelles, simultanées, solo et aux médias sont conservées. La liste des actions centrées sur l’acteur et celle des actions physiques à cible sont explicites dans `resolution_wording.dart`. Aucun rôle ou paramètre d’exécution n’est modifié.

## 4. Effets persistants

Le nouveau composant de présentation affiche seulement :

```text
Effet actif
Pendant cette action, continue « Tirage des cheveux ».
1/3
```

Pour la personne qui reçoit :

```text
Effet actif
Pendant cette action, tu es toujours sous l’effet de « Tirage des cheveux ».
1/3
```

Le compteur suit `1/3`, `2/3`, `3/3`. Il est calculé depuis la durée et le compteur moteur existants ; le composant ne décrémente et ne persiste rien. La disparition demeure pilotée par le moteur. Les effets exprimés en tours conservent cette unité dans leur phrase. Aucun identifiant technique, liste de rôles ou texte intégral de carte n’apparaît dans ce bloc. Le pseudo ou son fallback sert lorsqu’il faut parler de l’autre personne.

Les 15 tests du nouveau composant couvrent les deux points de vue, les trois positions du compteur, Silence, la durée moteur et la disparition.

## 5. Confirmation vestimentaire

Pour la personne effectivement concernée, « Terminé » reste désactivé jusqu’à validation dans « Ajuster les vêtements ». Annuler ou fermer cette fenêtre ne confirme rien. Valider le nombre inchangé est une confirmation valable.

Le nombre explicitement confirmé est stocké dans l’état privé local, avec une clé comprenant le round et les usages vestimentaires résolus. Il est restauré après reconnexion et effacé lors du passage au round suivant. Ce même nombre est envoyé à la validation réseau existante. Le compteur suggéré utilise le nombre confirmé pour éviter une seconde soustraction.

Le contrôleur refuse lui aussi la clôture avant confirmation, indépendamment de l’état du bouton. L’autre joueur ne reçoit pas artificiellement le contrôle et peut terminer sa propre action. La détermination de la personne concernée reste celle déjà validée.

Tests : porteur A/B, valeurs finales 0/5/6, conservation après reconnexion, confirmation inchangée, absence de double soustraction, bouton désactivé avant validation et après annulation, contrôle absent chez l’autre joueur.

## 6. Silence

Action pour la personne silencieuse :

`Garde un silence complet pendant les 3 prochaines actions.`

Précisions :

`Ne parle pas et ne fais volontairement aucun bruit. Tu peux uniquement rompre le silence lorsqu’une décision de jeu nécessite de communiquer.`

Les textes sont adaptés à la troisième personne lorsque l’écran décrit le partenaire. Le bloc actif est :

```text
Effet actif
Pendant cette action, garde le silence.
1/3
```

Puis `2/3` et `3/3`. L’exception de communication et la durée métier restent inchangées.

## 7. Investigation de sortie et écran noir

### Cause déterministe reproduite

Deux demandes simultanées de retour à l’accueil pouvaient exécuter deux nettoyages/navigations. La première attendait l’écriture de l’historique ; la seconde, voyant l’historique déjà marqué comme enregistré, retirait la route de partie. La première reprenait pendant l’animation de retrait, alors que le widget était encore monté. Sa recherche de la route déjà retirée pouvait dépiler aussi l’accueil.

Le test exécuté sur une copie isolée de l’ancien écran reproduit `Bad state: No element` dans la navigation et l’absence du widget d’accueil. Journal : `.tooling/ux4-exit-reproduction-before.txt`. Le même scénario passe avec la correction.

La sortie partage maintenant une seule opération en cours. Les commandes de sortie sont désactivées pendant son traitement. La route et le navigateur sont capturés avant les attentes ; la navigation vérifie que la route existe encore, et ne retire pas une route racine. Un échec d’historique est journalisé et ne bloque pas la sortie. Un échec de nettoyage local produit un message et permet de réessayer.

### Nettoyage et restauration

- Le pointeur de session active est effacé avant le nettoyage du contrôleur.
- Les timers et générations d’écoute sont invalidés immédiatement.
- L’annulation des abonnements round et consentement ne bloque plus l’effacement local ; ses erreurs sont journalisées.
- Les sauvegardes privées sont ordonnées. Une sauvegarde déjà commencée doit se terminer avant l’effacement des clés round/partie, et aucune nouvelle sauvegarde ne peut les recréer après nettoyage.
- Les retours asynchrones d’application d’état et d’erreur ignorent un contrôleur nettoyé.
- La destruction du contrôleur de lobby invalide une restauration encore en attente. Les protections existantes contre une écriture tardive du pointeur de session sont conservées.
- Le délai de démarrage existant de 15 secondes couvre désormais aussi l’identité et le chargement initial du profil/questionnaire. Un résultat tardif ne peut pas remplacer l’écran de repli.

Tests ajoutés : double retour à l’accueil, sauvegarde privée en vol puis effacement définitif, annulation de consentement suspendue, nouvelle tentative après échec d’effacement, restauration de lobby terminée après destruction, identité de démarrage suspendue puis réponse tardive. Les tests existants de sortie, nettoyage du pointeur et nouvelle partie sont également repassés.

### Limite de la conclusion

La course de navigation explique un écran vide à la sortie et a été reproduite en test. Elle ne démontre pas, à elle seule, la cause du noir persistant après fermeture complète du processus sur l’émulateur A. Aucun nouveau test manuel sur les deux émulateurs n’a été effectué pendant cette passe. Il reste à vérifier ce scénario sur appareil ; si le problème persiste, les journaux de démarrage et de sortie devront être recueillis. Les protections de démarrage et de stockage couvrent des attentes et courses identifiées dans le code, sans prétendre reproduire tout le symptôme observé.

## Fichiers de cette passe

Production :

- `assets/catalog/source/profile_questions.v1.fr.json`
- `assets/catalog/concepts/active.fr.json`
- `assets/catalog/source/cards.v4.fr.json`
- `lib/domain/catalog/concept_editorial.dart`
- `lib/features/profile/radial_appreciation.dart`
- `lib/features/profile/catalog_profile_screen.dart`
- `lib/features/game/network_duel_screen.dart`
- `lib/features/game/network_duel_secret_store.dart`
- `lib/features/game/network_game_controller.dart`
- `lib/features/game/ui/card_hand_surface.dart`
- `lib/features/game/ui/resolution_wording.dart`
- `lib/features/game/ui/persistent_effect_notice.dart` (nouveau)
- `lib/app/bootstrap.dart`
- `lib/features/lobby/lobby_controller.dart`

Tests :

- `test/profile/v4_questionnaire_test.dart`
- `test/features/resolution_wording_test.dart`
- `test/features/card_hand_surface_test.dart`
- `test/features/network_multiround_test.dart`
- `test/features/persistent_effect_notice_test.dart` (nouveau)
- `test/app/bootstrap_test.dart`
- `test/features/lobby_test.dart`

Ce rapport est nouveau. Le rapport historique `docs/UX_GAMEPLAY_AUDIT_4_1_4_8.md` est conservé. Les autres fichiers déjà modifiés au début de cette passe restent dans le chantier local précédent.

## Résultats de validation

| Vérification finale | Résultat |
| --- | --- |
| Réseau multi-round + bootstrap | 321 tests réussis |
| Régressions ciblées : questionnaire, appréciation/profil, consentement, anatomie, vêtements, Recovery, effets, formulations, swipe et piment | 314 tests réussis |
| Suite Flutter complète | 1 429 tests réussis, contre 1 389 avant cette passe : 40 tests supplémentaires |
| `dart analyze` | 0 erreur, 0 avertissement, 39 informations préexistantes |
| `flutter analyze --no-pub` | 0 erreur, 0 avertissement, les mêmes 39 informations ; code de sortie 1 dû aux informations |
| Comparaison des diagnostics | Identiques à la référence, en normalisant les numéros de ligne et la présentation Dart/Flutter |
| `git diff --check` | Réussi |
| Fichiers préexistants protégés | Aucune différence d’empreinte |

Journaux : `.tooling/ux4-followup-targeted-final.txt`, `.tooling/ux4-followup-regressions.txt`, `.tooling/ux4-followup-full-suite.txt`, `.tooling/ux4-followup-dart-analyze.txt`, `.tooling/ux4-followup-flutter-analyze.txt`.

## SQL et état Git

Aucune nouvelle migration n’est nécessaire pour cette passe. `supabase/migrations/202610230001_gameplay_ux_confirmations.sql` est inchangée, n’a pas été réappliquée et reste la migration déjà appliquée manuellement par l’utilisateur. SHA-256 : `27f112849d6ed82c53b37158d18b87e5cf9a5ae03abc297f8f4831efdc368c0e`.

Les fichiers non suivis préexistants et `supabase/.temp/` ont été vérifiés par empreinte contre la copie initiale : aucune différence. Aucun changement dans `tools/card_print_export/`. HEAD et origin/main restent sur `baf473ee9288678b2c82129afc254529fc22c1bc` ; index vide. Les changements de l’ancien chantier et de cette passe restent non commités ; aucun push effectué.

La prochaine validation manuelle doit surtout vérifier la roue sur les deux appareils, les trois actions d’un effet, la confirmation vestimentaire inchangée et après reconnexion, puis une sortie suivie d’un redémarrage complet sur chaque appareil.
