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
