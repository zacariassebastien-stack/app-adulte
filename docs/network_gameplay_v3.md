# Gameplay réseau V3

Le serveur conserve l’état public, l’ordre des phases, les PA et l’idempotence
par `commandId`. La main, le verrou, le nonce commit/reveal, les valeurs privées
et l’apprentissage restent sur l’appareil du joueur. Le catalogue runtime est
adapté depuis les champs V3 avant le calcul d’éligibilité.

Le commit/reveal existant reste inchangé. Une résolution utilise les valeurs
figées au commit. La négociation V3 est modélisée par un moteur pur borné qui
sépare proposition, réponse, adaptation, validation et résolution. Les cartes
engagées dans un compromis conservent leur direction native; seule la carte du
duel initial peut être inversée.

La migration `202610010001_gameplay_v3_recovery.sql` aligne Supabase sur le
seuil fixe de 10 PA et accepte le gain maximal V3 de 30 PA. La proposition
publique transmet toujours un gain nul avant accord, afin de ne pas révéler la
valeur personnelle.

La reprise conserve les secrets, la main, l’historique et le marqueur local des
rounds déjà appris. Ainsi une reconnexion ne répète ni exposition, ni
acceptation, ni dépense.

## `cardId` et `occurrenceId`

Le protocole conserve `cardId` pour retrouver le contenu et `occurrenceId`
pour cibler l’exemplaire. Le choix commit/reveal place l’occurrence dans le
payload canonique privé; elle ne devient publique qu’avec la révélation
autorisée. Les enchères, compromis, corruptions et Recovery transportent
également l’occurrence et le serveur refuse les doublons d’identité.

L’état public de session contient l’orientation hybride, le numéro de cycle,
l’intensité, le mode Infini et un résumé neutre des pénuries. Les ordres de
deck, mains, verrous, profils, exclusions et apprentissages restent locaux.
Une continuation conserve les PA et change seulement le cycle et, lorsque
demandé, l’intensité.

## Annulation avant révélation et fermeture

La migration `202610020002_safe_commit_cancel_and_session_close.sql` ajoute
deux commandes atomiques et idempotentes. `CANCEL_COMMIT` verrouille le round,
vérifie qu’il est encore en phase `COMMIT`, supprime uniquement le commit du
demandeur et laisse le client rendre la même occurrence à sa main. La version
locale du choix change avant tout nouveau commit, ce qui produit un nouveau
`commandId`, un nouveau nonce et un nouveau digest. Aucun PA ni apprentissage
n’est appliqué par l’annulation.

La transition du second commit vers `REVEAL` et l’annulation se sérialisent sur
le même verrou de ligne du round. Si la révélation gagne la course, le serveur renvoie
`ROUND_CANCEL_CLOSED` et le client conserve le choix engagé. Le reconnecté se
réconcilie avec l’absence ou la présence de son commit côté serveur.

`CLOSE_SESSION` ferme la session et marque ses rounds `SESSION_CLOSED` dans une
seule transaction idempotente. Cet état se distingue du `CLOSED` transitoire
qui ouvre le round suivant. Les appareils cessent alors le parcours et effacent
leur pointeur local de session active; aucune dépense ou résolution n’est
rejouée.
