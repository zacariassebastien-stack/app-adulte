# Lot 5 — raccordement ciblé, première tranche

État : **en cours, raccordement principal non réalisé**. La décision utilisateur
autorise une correspondance explicite avec les règles V4 pertinentes, puis demande
une proposition détaillée des associations sans équivalent avant raccordement.
Ce document présente cette proposition ; ses compositions ne sont pas actives.

## Ce qui est déjà implémenté

Le checkpoint du Lot 3 est complété par `reservations`, un dictionnaire privé
intention → concept. Il reste dans le même modèle ; aucun stockage ni service
supplémentaire n'est créé. Ce champ est facultatif à la lecture d'un checkpoint
du Lot 3, vide lorsque absent, et toujours sérialisé dans les nouveaux checkpoints.

- `reserve` immobilise une capacité, sans changer le quota restant.
- Le même intent/concept réserve une seule fois ; un intent ne change pas de concept.
- `availableFor` retire les capacités réservées du quota encore disponible.
- `releaseReservation` libère seulement une intention non engagée.
- `engage` remplace la réservation par un usage figé et une consommation définitive.
  Il ne peut pas prendre une capacité réservée par une autre intention.
- Reconnexion et retry conservent l'intention, l'usage et les compteurs.
- Une annulation après engagement ne restitue rien.

Ces opérations sont testées, **pas encore appelées par le contrôleur V4**.
Les flows actuels restent inchangés en attendant les correspondances ci-dessous.

## Points de contact identifiés, contrôleurs conservés

| Point existant | Adaptation ciblée prévue |
| --- | --- |
| `NetworkGameController._buildDeckCycle` / `_refill` | Quota initial du checkpoint + `ConceptDeckEngine.prepare`, exclusion des concepts déjà en main/réservés, tirage classe puis concept uniforme |
| `_runtime` / `hand` / `_networkCard` | Identité conceptuelle en main, aucun stade fixé par la pioche ; choix disponibles recalculés avec le contexte courant |
| `selectCard` / `confirmSelection` | Réservation persistée, résolution du choix, engagement idempotent avant émission, `NetworkUsageProjection` |
| `_restoreOrCreatePrivateState` / `_persist` | Ajouter le checkpoint dans `NetworkPrivateGameState`, le stockage privé/local existant ; aucun déplacement vers Drift |
| `_commitment` | Reconstruire depuis la projection figée du reveal, sans relire les règles actuelles du catalogue |
| `ChoicePayload` / commit-reveal | Faire transporter le document natif d'usage, conserver le calcul canonique du digest et le nonce persisté |
| `NetworkDuelScreen` | Main avec un concept, sélecteur des stades/variantes/zones disponibles ; pas de refonte de l'écran |
| `_prepareNextRound` | Clôturer l'usage engagé, conserver les quotas ; supprimer le schéma première/deuxième occurrence pour le parcours principal |

Les moteurs PA/duel, le suivi des phases, les subscriptions, les commandes
idempotentes, la continuation et la clôture restent la base. Le vieux contrôleur
`NetworkDuelController` est un prototype distinct : l'écran jouable instancie
`NetworkGameController`. Le contrôleur local est aussi utilisé par les fixtures
et démonstrations ; ne pas le prendre pour le runtime réseau V4.

Les parcours secondaires lisent encore `CardRuntimeState`, `NetworkCompromiseCardDto`,
`NetworkCorruptionDto`, `NetworkRecoveryDto` et les descripteurs d'apprentissage.
Leur migration ne doit pas être cachée derrière un pont global ancien/nouveau.
Leur contrat nécessaire au parcours principal sera adapté au minimum, avec dette
précise pour le Lot 6. Aucun ancien constructeur de deck n'est supprimé dans cette
tranche : ses consommateurs n'ont pas encore été raccordés.

## Correspondance : règle générale proposée

L'inventaire `catalog/concept_runtime_correspondence_draft.json` couvre les 56
concepts avec les sources candidates réellement présentes. Ce sont des pistes
d'inspection, **pas une validation de toutes les variantes historiques**.

Les concepts, textes, IDs de stades/variantes, zones, piments et capacités viennent
exclusivement de `active.fr.json`. Ne pas reprendre `baseEngagementLevel`,
`chili_level`, fréquence, répétabilité ou activation des anciennes cartes pour
déterminer la pioche ou le quota.

Pour les équivalents directs, reprendre les préférences atomiques, directions et
prérequis techniques pertinents. Garder les calculs PA et les exclusions existants ;
ne créer ni score de remplacement, ni acceptation automatique. Ne pas attribuer
de PA aux tags ZONE/MATERIEL. Les tags utilisés sont déjà dans la taxonomie V3.

## Compositions proposées, à valider avant raccordement

### P1 — 022 Doigter vaginal

Proposition : reprendre de `variant.anal_manual.internal` les préférences
`PENETRER` + `DOIGTS`, la réversibilité FAIRE/RECEVOIR et l'exclusion de la distance,
avec la zone sémantique `VAGINAL` à la place d'`ANAL`. Ne pas prendre les règles
de pénétration avec le sexe. Le stade choisi impose exclusivement 3/4/4.

Cette composition est nouvelle : aucune définition vaginale avec les doigts
équivalente n'est présente dans le catalogue chargé. Les règles de profil
existantes s'appliqueraient à ces deux préférences ; aucun nouveau calcul PA.

### P2 — 065 Footjob

Proposition : préférence `MASTURBATION` reprise de `card.masturbate_partner`,
zone sémantique `PIEDS`, direction réversible FAIRE/RECEVOIR et distance exclue.
Piment réel 3, aucun supplément de zone sur cette pratique intrinsèque.
`card.feet_play` décrit un massage des pieds : sa préférence MASSER ne convient
pas à ce concept. Ne pas inventer une préférence FOOTJOB et ne pas noter PIEDS.

À valider : MASTURBATION seule ou une autre combinaison des préférences existantes.
Cette décision change l'éligibilité et la valeur personnelle, pas seulement le nom.

### P3 — 045 / 047 Photo et vidéo mutuelles

Proposition : direction MUTUEL pour la participation à l'action, sans inversion
directionnelle ni tirage FAIRE/RECEVOIR. La spécification permet une image des deux
joueurs, y compris pendant une pratique sexuelle : **cela ne signifie pas que
chacun doit produire puis envoyer un fichier**. Ne pas ajouter ce double échange.
Les capacités de capture/envoi/réception existantes s'appliquent aux rôles médias
effectivement résolus. Chaque client utilise ses propres préférences ; pas de
fusion des profils ni de valeur privée du partenaire inventée.

- Photo : `PHOTO` ; vidéo : `VIDEO`. Reprendre `ENVOYER` si le parcours résolu
  implique un envoi. `SOUS_VETEMENTS` uniquement lorsque le choix le demande.
- Proposer `ETRE_REGARDE` pour les participants représentés, plutôt que dépendre
  de sa présence inégale dans les anciennes variantes. Cette association affecte
  la valeur personnelle et doit être validée.
- Piments et stades restent ceux du nouveau catalogue : **1/2/4 pour les deux**.
- Une pratique sexuelle effectivement choisie au dernier stade ne peut pas
  contourner ses exclusions : figer son choix/règles pertinents avec l'action
  média. Ne pas créer un autre usage/quota ou une pratique par défaut par déduction.

À valider : PHOTO/VIDEO + ETRE_REGARDE, avec ENVOYER seulement si l'envoi est
effectivement requis ; participation MUTUEL sans double capture/envoi obligatoire.
Le mode concret des photos mutuelles à distance reste à préciser : ne pas
supposer une présence physique commune, ni inventer un montage.

### P4 — 049–052 Sextoys et variantes d'usage

Les sources existantes ne portent que SEXTOY et, pour le contrôle distant,
VIBRANT + CONTROLE_DISTANCE + CONTROLE. Elles ne distinguent pas les quatre
usages externe/phallus/insertion vaginale/insertion anale du nouveau catalogue.

Proposition de préférences par usage :

| Usage | Préférences proposées | Piment réel |
| --- | --- | --- |
| Externe | SEXTOY | 3 |
| Phallus | SEXTOY | 3 |
| Insertion vaginale | SEXTOY + PENETRER, zone VAGINAL | 4 |
| Insertion anale | SEXTOY + PENETRER, zone ANAL | 4 |

Pour 052, ajouter les préférences VIBRANT + CONTROLE_DISTANCE + CONTROLE déjà
présentes sur `card.v3.remote_toy_control`. Conserver ses trois prérequis de
session : sextoy, fonction vibrante et contrôle distant.

Directions proposées : 049 FAIRE/RECEVOIR ; 050 SOLO ; 051 choix FAIRE/RECEVOIR
ou MUTUEL conforme à l'option réellement jouée ; 052 FAIRE/RECEVOIR pour le rôle
de contrôle. Le choix MUTUEL de 051 doit être figé avant engagement, sans quota
supplémentaire ni duplication du concept.

La résolution devra sélectionner un accessoire concret compatible avec l'usage
et figer son identifiant, libellé et tags utiles. Le catalogue actuel ne contient
pas de matrice de compatibilité accessoire/usage : ne pas déduire qu'un booléen
`hasSextoy` autorise toutes les insertions. Réutiliser les données d'accessoires
existantes si elles le permettent ; sinon présenter ce manque avant branchement.
Ne pas ajouter arbitrairement lubrifiant/protection comme nouveau prérequis.

À valider : composition des préférences d'insertion, direction de 051 et règle
pour rejeter les accessoires dont la compatibilité d'usage n'est pas renseignée.

## P5 — Contradictions médias à trancher

- Photo nue : `DISTANCE_EXCLUE=true` coexiste avec une liste de modes incluant
  distance. En V4 l'intersection bloque la distance. Proposition : le média
  photo reste admissible à distance si capture/envoi/réception le permettent.
- Vidéo nue : modes historiques distance/hybrid ET `DISTANCE_EXCLUE=true` ;
  en contexte strict distance ou présentiel, ces contraintes se contredisent.
  Proposition : même règle média que ci-dessus, sans exclusion de distance
  liée à la nudité. **À valider**, pas corrigé par cette inspection.
## P6 — Autres correspondances nécessitant une précision

- 004 Jeu de bouche : les sources lécher/sucer imposent des zones intimes.
  Il faut sélectionner la technique/préférence pertinente sans imposer ce tag
  à toutes les nouvelles zones. Ne pas copier une ancienne action intime sur
  chaque zone du nouveau concept.
- 024 Jeu intime est un joker. L'ancienne source `manual_intimate` documente
  elle-même une ambiguïté CARESSER/MASTURBATION/PENETRER+DOIGTS et ne suffit pas
  à définir ses pratiques autorisées. La pratique effectivement choisie doit
  résoudre les règles avant engagement ; pas de joker contournant les exclusions.
- 013 Changement complet de tenue : l'ancienne carte costume/tenue légère
  n'est qu'une piste. Elle ne définit pas sans ambiguïté le nouveau changement
  complet ni ses conséquences vestimentaires.

Ces cas concernent des données de gameplay, pas une raison de réécrire le runtime.

## HYBRID : inspection du défaut et correction prévue

`NetworkGameController` initialise `_context` en `face_to_face`/`TOGETHER`.
`switchOrientation` transmet au serveur mais `_apply` ne met pas ce contexte à
jour. `_buildDeckCycle` filtre avant de créer les deux anciens paquets : changer
seulement `_context.mode` ne récupère donc pas les concepts déjà éliminés.
De plus, `_networkCard(variantId: ...)` contourne la réévaluation d'éligibilité.

La correction doit donc accompagner `_refill` et le calcul dynamique des choix :
orientation canonique du round → contexte courant → éligibilité → pool conceptuel.
Aucun paquet figé et aucune pondération 70/30 dans ce parcours. Pas de nouvelle
décision d'orientation proposée. **Le défaut reste présent dans le runtime actuel** ;
aucune correction partielle n'est présentée comme un raccordement réussi.

## Validation de cette tranche et suite

34 contrôles purs d'usage passent, dont six nouveaux sur réservation, annulation,
transfert à l'engagement, absence de double consommation, protection des autres
réservations et reprise sérialisée. Analyse Dart ciblée sans problème.
Les limites Flutter/shared_preferences/Drift antérieures restent inchangées ;
aucune dépendance ni architecture n'est modifiée pour les contourner.

Après validation des correspondances : raccorder le parcours principal aux
méthodes du tableau, vérifier la sélection dynamique/UI et supprimer les anciens
constructeurs dès que leur dernier consommateur a migré. Pas de double pioche
activée pour contourner les cas non renseignés.

La migration du Lot 4 reste créée/non déployée. Déploiement seulement après
raccordement de tous les payloads nécessaires (dont Lot 6), scénarios SQL et
validation coordonnée à deux clients. Cette tranche ne rend pas la bascule sûre.
