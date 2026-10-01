# Plan de validation manuelle sur deux émulateurs

Ce protocole est préparé pour une campagne ultérieure. Aucun émulateur n’a été lancé pendant sa rédaction. Utiliser deux AVD propres, appelés A et B, et conserver les journaux séparés. Les valeurs Supabase doivent être fournies par variables locales ou `--dart-define`, sans les copier dans les comptes rendus.

## Préparation commune

Relever le SHA testé, les identifiants des deux appareils et la version de l’APK. Construire une seule fois un APK debug propre, puis installer exactement ce fichier sur A et B. Avant chaque séquence, vider seulement les journaux, pas les données, sauf indication contraire.

En cas d’échec, relever sur chaque appareil : heure, phase publique, round, `commandId` si visible dans les logs, code PostgREST nettoyé, dernière transition locale, et capture d’écran. Ne jamais relever nonce, token, clé, consentement privé ou valeur personnelle adverse.

## 1. Build APK debug propre

- **Précondition :** dépôt propre, SHA attendu, SDK disponible.
- **Action A :** aucune.
- **Action B :** aucune.
- **Action :** nettoyer, récupérer les dépendances puis construire l’APK avec les `--dart-define` locaux.
- **Attendu :** build unique réussi et chemin/empreinte SHA-256 de l’APK consignés.
- **Si échec :** sortie du build, versions Flutter/Dart/Gradle, sans secrets.

## 2. Installation sur A et B

- **Précondition :** deux AVD complètement démarrés et APK identifié.
- **Action A :** installer l’APK puis lancer à froid.
- **Action B :** installer le même APK puis lancer à froid.
- **Attendu :** le splash disparaît et le lobby s’affiche sur les deux appareils.
- **Si échec :** `adb -s <id> logcat -d`, état du package et capture.

## 3. Création et reconnexion des profils

- **Précondition :** application au lobby, données propres.
- **Action A :** créer le profil A et terminer le swipe initial.
- **Action B :** créer le profil B et terminer le swipe initial.
- **Attendu :** valeurs d’amorçage 3/8/20/exclu persistées localement ; après relance, chaque appareil retrouve uniquement son profil.
- **Si échec :** étape du bootstrap, version de base locale, présence de l’entrée de profil.

## 4. Création de session

- **Précondition :** deux profils disponibles et réseau actif.
- **Action A :** créer une session et afficher son code.
- **Action B :** rejoindre avec ce code.
- **Attendu :** lobby 2/2 avec identités publiques correctes.
- **Si échec :** code d’erreur réseau nettoyé, état public, compte des participants.

## 5. Synchronisation réseau

- **Précondition :** lobby 2/2.
- **Action A :** lancer la partie.
- **Action B :** attendre la transition synchronisée.
- **Attendu :** même session/round/phase publique ; chaque main reste privée.
- **Si échec :** séquences d’événements et dernière révision reçue.

## 6. Duel simple

- **Précondition :** premier round en sélection.
- **Action A :** choisir puis engager une carte.
- **Action B :** vérifier qu’elle reste secrète, puis choisir et engager.
- **Attendu :** commit/reveal valide, révélation simultanée, résolution identique et une seule dépense PA par joueur.
- **Si échec :** phases COMMIT/REVEAL/READY et code RPC, sans payload ni nonce.

## 7. Duel avec enchère

- **Précondition :** fixture ou cartes menant à une enchère.
- **Action A :** proposer une modification.
- **Action B :** accepter ou répondre selon le scénario.
- **Attendu :** résultat final identique, coûts appliqués une fois, seules les cartes du compromis accepté alimentent l’apprentissage.
- **Si échec :** état public d’enchère, identifiants de cartes publics après révélation, commandes dédupliquées.

## 8. Inversion

- **Précondition :** rôle dirigé révélé et inversion disponible.
- **Action A :** demander l’inversion.
- **Action B :** terminer la résolution.
- **Attendu :** puissance du duel inchangée ; apprentissage A/B enregistré selon les rôles finaux FAIRE/RECEVOIR.
- **Si échec :** snapshot de duel, rôles avant/après et agrégats locaux concernés.

## 9. Compromis multi-cartes

- **Précondition :** fixture d’enchère avec au moins deux cartes acceptées.
- **Action A :** construire le compromis.
- **Action B :** l’accepter.
- **Attendu :** chaque carte unique compte une fois pour chacun, avec son propre piment et son rôle final.
- **Si échec :** identités publiques des cartes après révélation et compteurs avant/après.

## 10. Changement d’orientation hybride

- **Précondition :** session hybride et pool comportant les deux groupes.
- **Action A :** sélectionner l’orientation distance.
- **Action B :** observer plusieurs tirages de fixture, puis sélectionner face à face.
- **Attendu :** pondération 70/30 puis 30/70 sur les groupes éligibles ; `DISTANCE_EXCLUE` reste possible.
- **Si échec :** tailles des pools éligibles, poids calculés et orientation active.

## 11. Persistance après relance

- **Précondition :** au moins un round terminé et des compteurs d’apprentissage présents.
- **Action A :** forcer l’arrêt puis relancer.
- **Action B :** faire de même.
- **Attendu :** reprise cohérente, aucun état privé croisé, agrégats sparse conservés sans double comptage.
- **Si échec :** version de schéma local, phase persistée et compteurs avant/après.

## 12. Confidentialité des profils

- **Précondition :** profils A et B avec notes différentes.
- **Action A :** parcourir lobby, sélection, attente, révélation.
- **Action B :** faire les mêmes vérifications.
- **Attendu :** aucune main, note, estimation, source ou proposition adverse dans l’UI, les DTO publics ou les logs.
- **Si échec :** nom du champ exposé et phase, en masquant sa valeur.

## 13. Absence de fuite de consentement

- **Précondition :** une préférence exclue uniquement sur A.
- **Action A :** vérifier le filtrage local et déclencher un STOP sur un autre contenu.
- **Action B :** observer les états publics.
- **Attendu :** B ne peut déduire ni l’auteur ni la raison d’un filtrage/refus ; STOP n’ajoute aucune résistance.
- **Si échec :** type de donnée ou message révélateur, sans contenu privé.

## 14. Mise à jour des statistiques

- **Précondition :** fixture avec une carte exposée, une jouée, une verrouillée et une ignorée.
- **Action A :** terminer le round selon la fixture.
- **Action B :** terminer avec le rôle opposé.
- **Attendu :** compteurs locaux exacts ; ignorée sans résistance ; verrouillée comme attraction ; résultat selon rôles finaux.
- **Si échec :** clé sparse, delta de chaque compteur et rôle final.

## 15. Proposition de profil accélérée

- **Précondition :** build debug avec une fixture locale explicitement activée, jamais en release.
- **Action A :** charger 10 preuves équivalentes puis 3 confirmations pour une source initiale/auto.
- **Action B :** charger 20 preuves puis les confirmations pour une source manuelle.
- **Attendu :** proposition uniquement après les seuils, saut direct depuis 20 possible, refus suivi d’un cooldown de 20 preuves, exclusion immuable.
- **Si échec :** catégorie de référence, estimation, occurrences équivalentes, confirmations et cooldown.

La fixture doit appeler le moteur pur avec des événements déterministes et injecter uniquement un état privé local. Elle ne doit pas écrire de faux événements réseau. Avant d’ajouter ce crochet à l’application, les mêmes scénarios s’exécutent par les tests ciblés :

```powershell
.\.tooling\flutter\bin\flutter.bat test test\engines\profile_learning_engine_test.dart
.\.tooling\flutter\bin\flutter.bat test test\engines\hybrid_draw_weighting_test.dart
```
