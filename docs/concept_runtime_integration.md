> **Réconciliation V4 : décisions finales.** P3 est corrigée : 045 utilise
> PHOTO_MUTUELLE principale @ MUTUEL, 047 VIDEO_MUTUELLE principale @ MUTUEL ;
> PHOTO/VIDEO sont des familles non notées et ETRE_REGARDE est absent de ces
> deux concepts. Les formulations P3 antérieures ci-dessous sont historiques.
> Pour 013 uniquement, TENUE@SOI utilise initialement TENUE@FAIRE (Q05 « Moi »).
> Le questionnaire V4 reste intact hors adaptation de la valeur UNSURE à 18.
> Voir `merge_origin_main_lot6.md` pour le raccordement définitif.

# Lot 5 — raccordement ciblé du runtime V4

Note de suivi : ce document décrit le checkpoint Lot 5. Le [Lot 6](concept_secondary_integration.md)
remplace ses adaptations secondaires temporaires et en détaille les suppressions.
Les limites historiques ci-dessous ne doivent pas être prises pour le bilan actuel.

État : parcours principal raccordé dans le code, contrôles purs réussis ; exécution
Flutter et validation à deux clients non réalisées. Migration du Lot 4 toujours
créée et non déployée. Ce checkpoint ne constitue pas une bascule de production.

## Base conservée et parcours raccordés

`NetworkGameController` et `NetworkDuelScreen` restent les contrôleur et écran
existants. Les phases, subscriptions, commandes, calculs PA et moteurs de duel
restent leur base. Aucun contrôleur concurrent ni stockage Drift n'est ajouté.

| Point existant | Adaptation réalisée |
| --- | --- |
| `_buildDeckCycle` / `_refill` | Stock conceptuel et capacités 006/007 ; candidats actuels ; classe dynamique puis concept uniforme ; exclusion des concepts déjà en main/engagés ; aucun biais HYBRID |
| Main / `_networkCard` | Identité conceptuelle sans variante fixée au tirage ; choix réévalués selon plafond, profils, contexte et prérequis |
| Sélection | Réservation persistée, dialogue des actions/stades/zones/techniques admissibles, piment réel affiché |
| `confirmSelection` | Engagement par intention stable, snapshot figé, consommation définitive unique ; projection et nonce persistés avant émission |
| `_commitment` | Reconstruction depuis la projection engagée, sans recalcul depuis le profil/catalogue courant |
| Retry / restauration | Même usage, snapshot, nonce et commande ; un commit absent est rejoué ; intention d'annulation persistée et reprise après interruption |
| Manche suivante | Retrait de l'usage engagé et refill selon quota restant ; pas de seconde occurrence artificielle DISCARD/EXHAUSTED |
| Changement d'orientation | Orientation canonique du round appliquée au contexte avant éligibilité ; aucun paquet préfiltré |

Une annulation avant engagement libère la réservation. Une annulation après
engagement ne rembourse aucun quota. Chaque nouveau cycle archive le checkpoint
précédent ; les capacités vestimentaires partent du nombre initial, conservé,
et ne sont pas recréées depuis les vêtements modifiés pendant la partie.
Les concepts déjà en main devenus inadmissibles restent identifiés en main et
indisponibles ; un nouveau stade se débloque sans remplacer le concept.

`applyResolvedContext` accepte les réglages déjà résolus par les mécanismes
existants. Le Lot 5 ne crée pas de protocole d'accord sur les réglages. Le
producteur réseau des variations de piment/capacités n'est pas ajouté ici.
Les usages engagés restent indépendants des variations ultérieures.

## Catalogue et correspondances validées P1–P6

`assets/catalog/concepts/active.fr.json` reste la seule référence pour les 56
identités actives, actions, stades, zones, textes, quotas et piments.
`assets/catalog/concepts/runtime_rules.fr.json` nomme explicitement les sources
V4 dont les préférences, directions et prérequis pertinents sont repris.
`ConceptRuntimeCatalog` exprime ces règles dans les types de définition déjà
consommés par les moteurs V4. Aucun poids ni quota de l'ancien catalogue ne
participe au nouveau tirage. Le brouillon de correspondances est retiré.

| Groupe validé | Règles appliquées et différence avec les sources V4 |
| --- | --- |
| P1 — 022 | Source `card.anal_manual`, variante interne : PENETRER + DOIGTS ; zone VAGINAL remplace ANAL ; FAIRE/RECEVOIR ; distance exclue ; aucun matériel obligatoire ; piments intrinsèques 3/4/4 |
| P2 — 065 | Source `card.masturbate_partner` : MASTURBATION ; PIEDS sémantique sans PA propre ; FAIRE/RECEVOIR ; distance exclue ; piment 3 |
| P3 — 045/047 | Sources photo/vidéo explicites du fichier de correspondances ; participation MUTUEL ; PHOTO/VIDEO + ETRE_REGARDE ; stades 1/2/4 ; ENVOYER et capacités de transfert uniquement si un envoi est requis ; aucune pratique sexuelle implicite ajoutée au stade explicite |
| P4 — 049–052 | Sources `card.v3.sextoy_play` et `card.v3.remote_toy_control` ; externe/phallus SEXTOY, piment 3 ; insertions SEXTOY + PENETRER et zone VAGINAL/ANAL, piment 4 ; 050 ajoute MASTURBATION et SOLO (direction SOI existante) ; 052 conserve VIBRANT + CONTROLE_DISTANCE + CONTROLE |
| P5 — 044/046 | Sources photo/vidéo ; contradiction DISTANCE_EXCLUE retirée ; trois contextes autorisés si capacités médias nécessaires satisfaites |
| P6 — 004 | Sources oral/analingus : technique LECHER ou SUCER choisie explicitement ; FAIRE/RECEVOIR ; distance exclue ; zone sémantique et piment base 1 + modificateur ; aucune préférence sexuelle génitale/anale héritée automatiquement |
| P6 — 024 | Le joker propose une pratique intime existante compatible ; emprunte ses règles mais conserve concept/usage/quota 024 ; pratique et action choisies figées ; pas de contournement du plafond ni des exclusions |
| P6 — 013 | Source `card.v3.costume_and_light_outfit` ; TENUE et SOLO uniquement, trois contextes ; aucun ETRE_REGARDE/DEGUISEMENT/TENUE_LEGERE ajouté ; résultat vestimentaire réel enregistré séparément du snapshot engagé |

Le résolveur de 024 considère explicitement les pratiques 019, 020, 021, 022,
023, 025, 026, 027, 028, 029, 030, 031, 049, 050, 051, 052 et 065. Les accessoires restent absents des choix
tant que leur inventaire compatible n'existe pas. Les préférences requises
FAIRE/RECEVOIR doivent toutes permettre une même direction cohérente.
La formule PA existante est conservée, sans nouvelle règle de combinaison.

## Accessoires : données manquantes identifiées

Inspection : `EngineSessionContext.accessories` contient des IDs, avec des flags
comme `hasSextoy`. `PlayerGameProfile.preferences` porte les préférences par
élément ; `LocalProfile` porte identité et dates. Aucun champ caché ou producteur
d'inventaire concret portant les tags validés n'a été trouvé. Ces modèles de
profil et leurs stockages ne sont pas modifiés dans ce lot.

Le contrat pur `accessory_compatibility.dart` prépare : ANAL, VAGINAL, BUCCAL,
PHALLUS, EXTERNE, VIBRANT ; tous les tags requis sur le même accessoire ; clé de
préférence pour l'ensemble exact de tags ; aucun filtre de cible par propriétaire.
052 ajoute VIBRANT aux tags de l'usage et conserve les exigences de contrôle.
Aucun tag n'est déduit d'un ID, nom ou booléen.

**049–052 restent indisponibles dans le runtime** tant que les données concrètes
et leur producteur ne sont pas implémentés. La sélection de l'accessoire concret,
sa préférence, ses tags figés et le choix FAIRE/RECEVOIR ou MUTUEL de 051 devront
être raccordés sur ces données. Aucun inventaire ou fallback permissif n'est créé.

## Identité, persistance et compatibilité temporaire

Le checkpoint privé/local existant stocke usages + quotas + intentions/réservations,
cycles précédents et révélation active. Pas de nouveau stockage ni de migration
Drift. `usage_id` est canonique dès l'engagement ; le payload principal natif
n'émet pas d'alias `occurrence_id`. `ChoicePayload.fromUsage` transporte la
projection du Lot 4 ; le calcul canonique du digest reste inchangé.
Le DTO du compromis initial conserve l'action native complète et son usage,
y compris après sérialisation ; l'affichage engagé relit le snapshot figé.

Restes temporaires à traiter au Lot 6 :

- `CardRuntimeState` et cache privé utilisent encore des noms `card_id`,
  `variant_id`, `occurrence_id`. Pour un usage engagé principal, cette dernière
  valeur est le vrai usageId. Le checkpoint reste la source canonique.
- `ChoicePayload` conserve son ancien constructeur pour les prototypes et les
  consommateurs secondaires ; il n'est pas utilisé pour engager le parcours principal.
- Les propositions/adaptations de compromis, inversions de DTO, offres de
  corruption, conditions Recovery, lifecycle secondaire et apprentissage doivent
  migrer vers les usages et données figées. Leurs parcours ne sont pas déclarés
  fonctionnellement validés par ce lot.
- Les effets figés existent, mais leur application et synchronisation complète
  entre clients restent à vérifier au Lot 6. Pour 013, le compte réel est saisi
  et enregistré localement une fois par usage ; le partage des résultats
  vestimentaires et leur réconciliation entre clients restent à raccorder.
- Les anciens compteurs de paquets exposés à l'UI représentent désormais le
  même nombre de concepts admissibles ; `DeckShortage` et états de cycle ont
  encore des consommateurs DTO/UI. Nettoyer ces noms/consommateurs ensemble.

Un ancien checkpoint de développement sans checkpoint conceptuel est refusé
explicitement et demande une nouvelle session ; aucune conversion approximative
ni second moteur n'est maintenu. Un serveur sans `usage_contract_version: 1`
est refusé avant engagement. Cette garde ne constitue pas un déploiement.

## Suppressions réalisées et consommateurs restants

Retirés : `SessionDeckBuilderV3`, `SessionDeckBuildResult`, `DeckCandidateV3`,
`DeckSubstitution`, `HybridSessionDecks` et `_compose`/`_repeatTo`,
`SessionDeckRuntime.draw`, `_targetBySpice`, `HybridDrawWeighting`, son export
et ses tests ; les deux paquets privés, la duplication miroir, l'évitement récent
et les tests figant ces anciens mécanismes ont aussi été retirés.

`session_deck_builder.dart` ne conserve que `DeckShortage`, les orientations et
les choix/états de cycle encore consommés. `DrawEngine` reste consommé par
`LocalGameController`, `NetworkDuelController` (prototype) et `simulation/runner`.
Il n'est plus appelé par le contrôleur réseau principal. Les sources V4 restent
consommées par les correspondances de règles, les outils et ces prototypes ;
leur suppression globale doit suivre la migration de ces consommateurs.

## Vérifications et déploiement

123 contrôles purs réussis : catalogue 23, deck 31, usage 34, projection réseau 13,
raccordement pur 22. Audit migration : 16 contrôles structurels réussis, dont
les 11 migrations historiques inchangées octet pour octet. Cet audit ne remplace
pas l'exécution PostgreSQL des scénarios SQL préparés.

Analyse Dart ciblée des composants et tests modifiés : aucun problème.
Analyse explicite du stockage privé : six erreurs liées à la dépendance locale
`shared_preferences` absente (URI + cinq références), limitation conservée.
Le runner standard n'a exécuté aucun test : résolution du package `test` bloquée
par une erreur réseau vers pub.dev. Les limites Flutter/Drift précédentes ne
sont pas déclarées résolues. Aucune dépendance n'a été modifiée ; seules deux
entrées d'assets ont été ajoutées au manifeste.

Cinq scénarios contrôleur sont préparés : réservation/annulation avant engagement,
reprise du snapshot, changement de contexte sans remplacement de main/capacités,
retry d'un commit non enregistré, reprise d'une annulation interrompue. Leur
analyse passe, mais ils ne sont pas exécutés avec le runner Flutter.

Migration `202610150001_concept_usage_contract.sql` toujours inchangée et non
déployée. Bascule recommandée seulement après Lot 6, raccordement des accessoires
ou périmètre explicitement accepté sans eux, exécution des scénarios SQL et
validation coordonnée à deux clients du nouveau contrat. Ne pas déployer ce
checkpoint seul sur le runtime distant actuel.
