# Phase 3 — moteur pur

## Architecture

Les modèles purs sont dans `lib/domain/game/`; les moteurs sont dans
`lib/engines/`. Ils n'importent ni Flutter, ni Drift, ni Supabase, ni réseau.
`ProfileEngine` et `AnalyticsEngine` sont seulement réservés comme interfaces.

`BalanceConfig` centralise PA initiaux, taille de main, seuil Recovery, courbe
et cap d'écart, coûts 🌶️, poids de tirage, décroissance anti-répétition et
distributions de style. Ces valeurs sont provisoires.

## Consentement et éligibilité

`EligibilityEngine` applique les filtres absolus avant tout scoring et retourne
des raisons structurées. Seul `ACCEPTED` autorise ; `DISCOVER`, une note, une
capacité ou un accessoire ne valent jamais consentement. Une exclusion parent
bloque les descendants, tandis qu'une acceptation parent n'accepte rien en
dessous. FAIRE vise l'acteur volontaire et RECEVOIR le partenaire ; BOTH exige
les deux profils. Une combinaison explicite exige son propre élément.

Les règles techniques typées supportent conditions de mode, état actuel
TOGETHER/SEPARATED, état physique, vêtements par joueur, flags, rencontre
temporaire, médias, ainsi que groupes ALL/ANY pour accessoires ou capacités.
Les cartes ouvertes n'accordent que leur cadre déclaré : toute action concrète
ajoutée à l'exécution apporte ses propres `ConsentRule`.

Les capacités stables sont PHOTO_CAPTURE, RECORDED_VIDEO, LIVE_CAMERA,
MEDIA_SEND et MEDIA_RECEIVE. L'adaptateur ajoute ces contrôles aux cartes du
catalogue qui capturent réellement un média. Le roleplay photographe simulé ne
reçoit aucune exigence caméra. La variante de contrainte physique ambiguë est
bloquée quand les joueurs sont séparés.

## Tirage, intensité et lifecycle

`DrawEngine` évalue d'abord l'éligibilité, puis les poids. Une source de hasard
est injectée ; un seed identique reproduit le tirage. Le cycle privilégie
unseen, puis seen_unplayed, puis played/discarded faute de variété. EXHAUSTED
est exclu. Le style SOFT/EPICE/INTENABLE ne change que les poids futurs.

L'intensité possède exactement cinq niveaux. Le niveau actif est un plafond ;
le coût d'un saut cumule les niveaux. Baisse et remontée déjà débloquée sont
gratuites avec accord mutuel. Une main ne change pas lors d'une baisse.

Le cycle est POOL → HAND → ENGAGED → DISCARD, puis DISCARD → HAND lors d'un
nouveau cycle. Seule une action de discard réellement accomplie en
corruption/recovery devient EXHAUSTED. Un seul verrou est conservé et il saute
à l'engagement. Les effets ne s'appliquent qu'après COMPLETED.

Le refresh contextuel n'est permis que pour une impossibilité contextuelle
nouvelle ; le chili et le consentement ne permettent pas un mulligan.

## Duel, enchère, corruption et recovery

`DuelEngine` crée un `CombatValueSnapshot` depuis la valeur du rôle volontaire.
La note et l'inversion ultérieures ne le modifient pas. Une égalité ne coûte
rien et n'a pas de tie-break automatique. Le gagnant initial dépense le coût
d'écart immédiatement, borné par ses PA et le cap configuré.

`AuctionEngine` permet une contre-enchère puis une défense finale, strictement
croissantes. Les PA engagés sont retirés immédiatement et aucune dette n'est
possible. Le coût du duel initial n'est pas recrédité.

`CorruptionEngine` donne une puissance numérique nulle aux actions promises.
Une carte refusée, promise ou skipped reste au discard ; seule une action
COMPLETED devient EXHAUSTED. Les cartes ENGAGED du round sont interdites.

`RecoveryEngine` s'ouvre entre les rounds au seuil configuré, une fois entre
deux duels normaux. Il ignore seulement le plafond 🌶️. Le gain additionne les
valeurs du joueur récupérant pour les rôles effectivement réalisés et peut
dépasser les PA initiaux. L'acceptation conditionnelle exige exactement une
carte du discard. `MUTUAL_PA_EXTENSION` ajoute le même montant aux deux.

## Confidentialité et événements

`CompleteGameState` conserve la vérité. `VisibilityProjection` produit un
`PublicState` sans mains, PA ni choix non révélés, et une
`PrivatePlayerProjection` limitée au joueur propriétaire. Elle respecte la
frontière `PrivatePlayerState` déjà définie et persistée en Phase 2. Masquer ne
fabrique aucune fausse valeur.

Les moteurs émettent des `GameEvent` compatibles avec l'EventLog : round,
sélection, commit, révélation, duel, PA, enchère, corruption, actions,
changements d'état, discard/exhaustion, fermeture, renoncement, STOP et
extension mutuelle. Les payloads refusent les champs média.

Une session ne se termine que par décision humaine ou fermeture technique ;
PA=0 et durée indicative ne sont jamais des conditions automatiques.
