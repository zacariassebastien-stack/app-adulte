# Spécification contenu V1 — structure de travail

## Axes du profil
- Affection et proximité
- Baisers
- Toucher et massage
- Vêtements et dévoilement
- Observation et mise en scène
- Initiative et contrôle
- Contraintes sensorielles
- Jeux de rôle
- Communication à distance
- Photo
- Vidéo enregistrée
- Caméra en direct
- Accessoires
- Contextes et ambiance

## Dimensions techniques des cartes
- Intensité éditoriale : 1 à 5
- Précision : ouverte / guidée / précise
- Mode : présentiel / distance / universel / rapprochement temporaire
- Participants : initiateur / partenaire / mutuel
- Direction : faire / recevoir / mutuel
- Média : aucun / photo / vidéo / direct
- Répétabilité
- Fréquence éditoriale
- Conditions dynamiques
- Effets sur état de session
- Inversion disponible
- Variantes disponibles

## Principe
Les catégories du profil expriment des limites et préférences.
Les tags décrivent les cartes.
Une carte peut utiliser plusieurs tags.
Une acceptation générale n'autorise jamais automatiquement une variante plus spécifique.
Une exclusion parent filtre les descendants concernés.


## Taxonomie hiérarchique V1

La taxonomie n'est pas une liste de cartes. Elle représente les préférences/limites que plusieurs cartes peuvent réutiliser.

### 1. Affection et proximité
- contact tendre
- câlin
- proximité corporelle
- corps contre corps
- être enlacé
- enlacer le partenaire

### 2. Baisers
- baiser
  - baiser prolongé
  - baiser avec langue
- zones embrassées
  - visage
  - cou
  - torse
  - ventre
  - zones intimes (validation spécifique)

### 3. Toucher et massage
- toucher
  - caresse tendre
  - caresse sensuelle
  - caresse intime
- massage
  - massage classique
  - massage sensuel
  - massage intime
- direction quand pertinente
  - faire
  - recevoir

### 4. Vêtements et dévoilement
- jeu avec les vêtements
  - retirer ses propres vêtements
  - retirer ceux du partenaire
  - être déshabillé
  - choisir la tenue du partenaire
- niveau de dévoilement
  - habillé
  - sous-vêtements
  - nudité
- mise en scène
  - effeuillage
  - strip-tease
  - regarder / être regardé pendant le dévoilement

### 5. Observation et mise en scène
- regarder le partenaire
- être regardé
- poser
- choisir une pose
- danse / défilé
- exhibition privée
- voyeurisme privé

### 6. Initiative, contrôle et pouvoir
- donner une consigne
- recevoir une consigne
- décider pour le partenaire
- laisser le partenaire décider
- domination
- soumission
- attente / contrôle du rythme
- interdiction temporaire de toucher
- immobilisation
- bondage léger
- yeux bandés

### 7. Sensoriel
- yeux fermés
- deviner au toucher
- température
- textures
- pression / intensité
- morsure
- griffure
- fessée

### 8. Pratiques intimes
Cette branche doit être plus détaillée et adaptative. L'acceptation du parent ne vaut jamais acceptation des descendants précis.
- stimulation manuelle intime
- masturbation
  - se masturber
  - devant le partenaire
  - masturber le partenaire
  - être masturbé
  - mutuelle
- stimulation orale
  - donner
  - recevoir
  - mutuelle / 69
- frottements intimes
- pénétration
  - vaginale
  - anale
- anal
  - contact externe
  - stimulation manuelle
  - stimulation orale
  - pénétration
- jeux avec poitrine / torse
- stimulation des tétons
- jeux avec les pieds
- facesitting
- simulations
  - simulation d'acte intime
  - simulation orale
  - simulation de pénétration
  - simulation de 69
  - simulation de facesitting

### 9. Jeux de rôle
- jeu de rôle en général
- deux inconnus
- photographe / modèle
- masseur / client
- maître / serviteur
- royauté / serviteur
- célébrité / fan
- livraison inattendue
- patron / employé adulte
- scénario médical adulte
- rencontre au bar

Chaque scénario est indépendant : accepter « jeu de rôle » ne signifie pas accepter tous les scénarios.

### 10. Communication à distance
- message coquin
- sexting
- consignes à distance
- recevoir des consignes à distance
- interaction synchrone
- interaction asynchrone

### 11. Photo
Consentement média indépendant.
- recevoir une photo
- envoyer une photo
- photo suggestive
- photo en sous-vêtements
- photo nue
- pose choisie par soi
- pose choisie par partenaire

### 12. Vidéo enregistrée
Consentement média indépendant.
- recevoir vidéo
- envoyer vidéo
- suggestive
- sous-vêtements
- nudité
- action mise en scène

### 13. Caméra en direct
Consentement média indépendant.
- appel vidéo
- apparaître à l'image
- nudité en direct
- recevoir une consigne en direct
- donner une consigne en direct

### 14. Accessoires et contexte
Les accessoires possèdent une disponibilité de session en plus du consentement.
- bandeau
- liens / attaches
- accessoires sensoriels
- accessoires de massage
- accessoires intimes
- douche
- bain
- chambre / lit
- autre pièce
- extérieur privé / contexte spécifique, si explicitement configuré

## Héritage et résolution

Règles:
1. EXCLU sur un parent interdit tous les descendants qui nécessitent ce parent.
2. ACCEPTÉ sur un parent n'accepte jamais automatiquement ses descendants.
3. NON_RENSEIGNÉ n'est ni un oui ni un non.
4. À_DÉCOUVRIR permet une suggestion privée de profil mais ne rend pas une action précise jouable.
5. Une carte précise exige que tous ses ProfileRequirements obligatoires soient explicitement compatibles.
6. Un élément peut avoir une valeur générale et, lorsque pertinent, des valeurs FAIRE et RECEVOIR.
7. Une CardRating/VariantRating explicite est prioritaire sur l'estimation issue de la taxonomie.

## Contrat profil -> carte

ProfileRequirement:
- element_id
- role: GENERAL | FAIRE | RECEVOIR
- requirement: REQUIRED | OPTIONAL | ONE_OF
- one_of_group_id nullable
- minimum_status: ACCEPTED
- applies_to_variant_id nullable

TechnicalRequirement:
- session_mode
- physical_state
- minimum_clothes_actor
- minimum_clothes_partner
- required_accessory
- required_media_capability
- temporary_meeting_allowed
- other dynamic predicate

Les ProfileRequirement servent au consentement/préférences.
Les TechnicalRequirement servent uniquement à déterminer si l'action est réalisable ici et maintenant.

## Exemple de composition

Carte: « Photo rien que pour toi »
Base:
- PHOTO:SEND = REQUIRED
- MEDIA_PHOTO = REQUIRED

Variante 🌶️1:
- PHOTO:SUGGESTIVE = REQUIRED

Variante 🌶️2:
- PHOTO:UNDERWEAR = REQUIRED

Variante plus explicite:
- PHOTO:NUDE = REQUIRED

La personne peut donc accepter la carte et ses premières variantes sans que cela autorise automatiquement la variante la plus explicite.

## Règle de combinaison

Si une carte combine plusieurs dimensions sensibles, l'acceptation séparée des dimensions ne vaut pas automatiquement consentement à leur combinaison.

Exemple abstrait:
A accepté + B accepté != A+B automatiquement accepté.

Une combinaison nouvelle peut avoir:
- son propre ProfileElement; ou
- une VariantRating explicite demandée avant première utilisation.

Le moteur choisit l'option la moins intrusive qui conserve un consentement explicite.

## Génération du questionnaire

Mode RAPIDE:
- questions racines et sous-branches nécessaires au catalogue de base;
- approfondissement seulement après acceptation;
- possibilité de compléter via recherche.

Mode GUIDÉ:
- parcours adaptatif;
- ouverture progressive des descendants acceptés;
- arrêt immédiat d'une branche exclue.

Mode APPROFONDI:
- exploration large des branches compatibles;
- toujours avec pruning des descendants d'un parent exclu.

Dans tous les modes:
- barre de recherche;
- modification ultérieure;
- aucune différence de puissance ou de contenu réservée à un mode de questionnaire.

## Règles de catalogue

Une carte doit être une action reconnaissable par le joueur, pas seulement un assemblage technique de tags.
Les tags peuvent être nombreux et combinatoires, mais le texte affiché est éditorialisé.
Les variantes portent les différences qui changent réellement l'action, l'intensité ou le consentement.
Les paramètres portent les variations numériques ou légères qui ne justifient pas une nouvelle carte.

CardParameter:
- id
- type: INTEGER | ENUM | BOOLEAN | DURATION_HINT
- allowed_values
- consent_relevant
- affects_state

Si un paramètre modifie substantiellement le consentement, il devient une variante ou déclenche une validation explicite; il ne reste pas un simple paramètre caché.


## Analyse de fin de partie

Le moteur de profil final travaille uniquement à partir d'événements de jeu autorisés.
Un refus, un STOP, un retrait de consentement ou une exclusion de profil n'alimente jamais un trait négatif.

### Axes comportementaux internes
Ces axes ne sont pas montrés comme des notes psychologiques. Ils servent seulement à sélectionner des intitulés humoristiques.

- AUDACE: valeurs personnelles élevées volontairement engagées, variantes proches du plafond actif.
- PRUDENCE: préférence volontaire pour valeurs plus basses, gestion conservatrice des PA.
- DEPENSE_PA: propension à engager des PA en enchère/déblocage.
- ECONOMIE_PA: conservation stratégique des PA.
- NEGOCIATION: fréquence et richesse des contre-propositions/corruptions.
- TENTATION: propositions d'actions supplémentaires ou répétitions.
- PROMESSE: quantité d'actions promises.
- REALISATION: ratio des actions promises effectivement réalisées, hors arrêts de consentement.
- INVERSION: recherche des inversions.
- INITIATIVE: fréquence d'actions initiées volontairement.
- RECEPTIVITE: fréquence des rôles reçus/acceptés lorsque le joueur choisit cette voie.
- VARIETE: diversité des tags/précisions joués.
- SPECIALISATION: répétition volontaire de familles de tags proches.
- ESCALADE: propositions/financement de montée 🌶️.
- MODERATION: maintien ou baisse volontaire du niveau actif.
- RECOVERY_RISK: recours à des récupérations à forte valeur.
- PROLONGATION: volonté de continuer via récupération/remontée commune.
- RENONCEMENT_STRATEGIQUE: victoires/actions abandonnées volontairement pour raison de jeu, distinctes du consentement.
- CHANGEMENT_STYLE: évolution Soft/Épicé/Intenable pendant la partie.

### Normalisation
Les traits sont calculés relativement aux opportunités réelles.
Exemple: 3 enchères sur 3 opportunités est plus significatif que 3 enchères sur 20.
Ne jamais comparer un joueur à une action qui lui était indisponible.

### Profils humoristiques candidats

Économie / PA:
- Ministre des Finances
- Gardien du Trésor
- Flambeur méthodique
- Kamikaze romantique

Négociation:
- Tentateur stratégique
- Marchand de tentations
- Diplomate très intéressé
- Négociateur sans scrupules (ton humoristique uniquement)

Promesses:
- Les yeux plus gros que le ventre
- Parole tenue
- Promesses, promesses…
- Il faut savoir tourner sa langue dans sa bouche avant de parler

Audace / intensité:
- Explorateur prudent
- Amateur de montée en température
- Accélérateur de particules
- Toujours un piment d'avance

Contrôle / inversion:
- Maître du contre-pied
- Retour à l'envoyeur
- J'avais un autre plan
- L'art de retourner la situation

Variété:
- Touche-à-tout
- Collectionneur d'expériences
- Fidèle à ses classiques
- Une idée fixe, mais une bonne

Prolongation:
- Encore un dernier tour
- Expert en prolongations
- Pas prêt à rendre les cartes

### Sélection finale
Chaque joueur reçoit:
- 1 archétype principal;
- 2 traits secondaires maximum.

Contraintes:
- éviter trois intitulés décrivant le même axe;
- minimum de données avant attribution;
- si données insuffisantes, utiliser un profil neutre;
- ne jamais exposer les notes 1–20 exactes du partenaire;
- ne jamais révéler indirectement une préférence exclue;
- ne jamais produire d'inférence sur la personnalité réelle, la sexualité ou la relation du joueur.

### Profil de duo
Produit seulement si double opt-in initial + double confirmation finale.
Utilise uniquement des tendances agrégées compatibles avec la confidentialité.

Axes duo possibles:
- niveau de négociation partagé;
- tendance à prolonger;
- variété collective;
- alternance initiative/réception;
- fréquence des inversions;
- dynamique de montée/descente 🌶️.

Si aucune tendance nette ou absence du double accord:
« Votre dynamique de duo n’a pas dégagé de tendance suffisamment marquée cette fois-ci. »

Le message est volontairement identique pour éviter d'indiquer lequel des deux n'a pas consenti.

## Protection contre les faux profils
Un trait nécessite:
- un minimum d'opportunités;
- un minimum d'événements;
- une marge suffisante sur les autres traits candidats.

Les seuils numériques seront calibrés par simulation, pas choisis arbitrairement avant les tests.

## Catalogue: séparation contenu / moteur
Le moteur ne connaît aucun intitulé sexuel en dur.
Il reçoit des CardDefinition/ProfileElementDefinition sérialisées.
Cela permet:
- d'étendre le catalogue sans modifier DuelEngine;
- de traduire le contenu;
- de tester un catalogue fictif;
- de distribuer différents ensembles de contenu;
- de versionner/migrer le catalogue.

Chaque définition possède:
- stable_id
- schema_version
- content_version
- locale_key
- tags
- requirements
- variants

Les sauvegardes référencent stable_id, jamais le texte affiché.


# Contrat de données pour l'implémentation

## Identifiants
Tous les objets de contenu ont un identifiant stable, indépendant du texte traduit.

Exemples:
- card.kiss
- card.private_photo
- variant.private_photo.suggestive
- profile.media.photo.send
- tag.media.photo
- role.actor
- role.partner

Un renommage éditorial ne change jamais stable_id.

## CardDefinition

CardDefinition:
- stable_id: string
- content_version: integer
- title_key: string
- description_key: string
- precision: OPEN | GUIDED | PRECISE
- frequency: COMMON | OCCASIONAL | RARE
- repeatability: REPEATABLE | SESSION_ONCE
- base_tags: list<TagId>
- profile_requirements: list<ProfileRequirement>
- technical_requirements: list<TechnicalRequirement>
- participants: list<ParticipantRole>
- inversion_policy: NONE | SWAP_ACTOR_TARGET | SPECIFIC
- variants: list<CardVariantDefinition>
- parameters: list<CardParameterDefinition>
- enabled: boolean

## CardVariantDefinition

CardVariantDefinition:
- stable_id
- card_id
- content_version
- title_key optional
- instruction_key
- chili_level: 1..5
- additional_tags
- removed_tags
- profile_requirements
- technical_requirements
- participant_overrides
- inversion_override optional
- parameters
- state_effects
- enabled

Une variante hérite de la carte puis applique ses ajouts/surcharges.

## ProfileElementDefinition

ProfileElementDefinition:
- stable_id
- parent_id nullable
- title_key
- description_key
- kind: PRACTICE | BODY_AREA | DYNAMIC | MEDIA | ROLEPLAY | CONTEXT | PREFERENCE
- directionality: GENERAL_ONLY | FAIRE_RECEVOIR
- searchable_keywords
- children_order
- explicit_acceptance_required: boolean
- enabled

## Rating utilisateur

UserPreference:
- profile_element_id
- status: UNSET | DISCOVER | ACCEPTED | EXCLUDED
- general_value nullable 1..20
- faire_value nullable 1..20
- recevoir_value nullable 1..20
- updated_at
- source: ONBOARDING | SEARCH | CARD_REVIEW | POST_SESSION | EVOLUTION_SUGGESTION

CardPreferenceOverride:
- card_or_variant_id
- status optional
- faire_value optional
- recevoir_value optional
- updated_at

## TagDefinition

TagDefinition:
- stable_id
- namespace
- title_key
- technical_only: boolean

Namespaces recommandés:
- practice.*
- media.*
- body.*
- dynamic.*
- staging.*
- sensory.*
- clothing.*
- context.*
- roleplay.*
- precision.*
- distance.*

Les tags techniques ne sont jamais présentés comme préférences à noter.

## TechnicalRequirement

TechnicalRequirement est déclaratif.
Types V1:
- SESSION_MODE_IN
- PHYSICAL_STATE_IS
- CLOTHES_AT_LEAST
- ACCESSORY_AVAILABLE
- MEDIA_CAPABILITY_AVAILABLE
- TEMPORARY_MEETING_ALLOWED
- SESSION_FLAG_IS

Aucun script arbitraire embarqué dans les données V1.
Le moteur possède une liste fermée de prédicats testables.

## StateEffect

Types V1:
- CLOTHES_DELTA
- SET_PHYSICAL_STATE_TEMPORARY
- RESTORE_PHYSICAL_STATE_AFTER_ACTION
- SET_SESSION_FLAG
- CLEAR_SESSION_FLAG

Les effets ne s'appliquent qu'après confirmation d'exécution.
Une action sautée n'applique aucun effet.

## Paramètres

CardParameterDefinition:
- stable_id
- type: INTEGER | ENUM | BOOLEAN | DURATION_HINT
- values/range
- selection_by: ACTOR | PARTNER | BOTH
- visibility: PUBLIC | PRIVATE_UNTIL_REVEAL
- consent_relevant
- state_relevant

Si consent_relevant=true et que le paramètre change substantiellement la pratique, les valeurs sensibles doivent être validées explicitement avant utilisation.

# Résolution d'éligibilité

Pour chaque CardDefinition:
1. vérifier enabled;
2. vérifier qu'elle n'est pas EXHAUSTED;
3. résoudre les exigences de base;
4. énumérer les variantes;
5. éliminer les variantes > chili_active;
6. éliminer les variantes incompatibles avec le profil;
7. éliminer les variantes incompatibles avec SessionState;
8. si aucune variante ne reste, carte inéligible;
9. sinon produire EligibleCard(card, eligible_variants).

Exception Recovery:
- ignore la limite chili_active/unlocked;
- n'ignore jamais consentement, exclusion, capacités média ou contraintes physiques impossibles.

# Valeur de duel

CombatValueSnapshot:
- player_id
- card_id
- variant_id
- role_at_commit
- personal_value
- committed_at

Une fois créé, le snapshot est immuable jusqu'à la fermeture du round.
L'inversion modifie le rôle d'exécution mais jamais personal_value du snapshot.

Si aucune note explicite nécessaire au duel n'existe:
- la carte ne peut pas être engagée avant que le joueur ait fourni sa valeur;
- une estimation de DrawEngine ne peut jamais devenir CombatValueSnapshot.

# DrawCandidate

DrawCandidate:
- card_id
- eligible_variant_ids
- novelty_score
- style_score
- chili_score
- personal_affinity_score
- tag_diversity_score
- precision_diversity_score
- editorial_frequency_score
- discard_penalty
- final_weight

Le calcul de poids est déterministe pour un état donné, sauf le tirage pseudo-aléatoire final.
Pour les tests, le générateur aléatoire doit accepter un seed.

# Versionnement du catalogue

Le catalogue livré avec l'app possède:
- schema_version
- catalog_version
- locale_version

Migration:
- stable_id conservé => historique conservé;
- élément supprimé => disabled, pas suppression physique immédiate;
- renommage => clés de traduction uniquement;
- variante restructurée => migration explicite des anciens IDs si nécessaire.

Une sauvegarde ancienne doit pouvoir être ouverte après mise à jour de catalogue sans perdre les préférences connues.

# Architecture Flutter proposée

lib/
- app/
- core/
  - ids/
  - errors/
  - security/
  - random/
- domain/
  - catalog/
  - profile/
  - session/
  - round/
  - media/
  - monetization/
  - analytics/
- engines/
  - eligibility/
  - draw/
  - duel/
  - auction/
  - corruption/
  - recovery/
  - intensity/
  - lifecycle/
  - profile_evolution/
  - final_profile/
- data/
  - local/
  - remote/
  - repositories/
  - catalog_loader/
- features/
  - onboarding/
  - profile/
  - lobby/
  - shared_phone/
  - game/
  - recovery/
  - final_profile/
  - settings/
  - store/
- sync/
- tests_support/

Principe:
domain et engines ne dépendent pas de Flutter UI.
Ils doivent pouvoir être exécutés dans des tests Dart purs et dans le simulateur.

# Phasage Codex

PHASE 0 — dépôt et garde-fous
- projet Flutter
- lint
- tests
- CI
- conventions IDs
- fixtures fictives non sexuelles pour tests moteur

PHASE 1 — domaine
- modèles immuables
- enums
- sérialisation
- validation de catalogue
- erreurs typées

PHASE 2 — stockage local
- Drift/SQLite
- migrations
- repositories
- profil local
- catalogue local
- sauvegarde session

PHASE 3 — moteur pur
- EligibilityEngine
- DrawEngine
- lifecycle
- DuelEngine
- AuctionEngine
- CorruptionEngine
- RecoveryEngine
- IntensityEngine
- EventLog

PHASE 4 — simulateur
- joueurs synthétiques
- parties automatiques
- métriques PA
- répétition
- distribution cartes
- calibration

PHASE 5 — UI hors ligne / téléphone partagé
- onboarding
- profil
- création session
- main
- transitions privées
- rounds complets
- fin de partie

PHASE 6 — compte et synchronisation
- Supabase Auth
- création/rejoindre session
- QR/code
- Realtime
- reconnexion
- commit/reveal
- politiques d'accès

PHASE 7 — médias
- permissions
- photo
- vidéo
- live
- durée de vie éphémère
- nettoyage
- tests de confidentialité

PHASE 8 — monétisation et thèmes
- ThemePack
- achats
- restauration
- suppression pub
- éventuel module publicité activable

PHASE 9 — durcissement
- tests réseau
- migrations
- reprise après crash
- confidentialité
- performance
- packaging Android/iOS/Windows

Chaque phase doit être validée par tests avant la suivante.
Codex ne doit pas modifier les règles de game design pour résoudre un problème technique sans documenter le conflit.

# Definition of Done V1 moteur

Le moteur V1 est considéré prêt lorsque:
- toutes les règles établies ont un test;
- un catalogue invalide est rejeté avec erreur explicite;
- une partie peut être sauvegardée/reprise à chaque frontière de round;
- le mode partagé fonctionne sans réseau;
- les secrets d'un joueur ne sont jamais exposés dans l'état public;
- le simulateur peut exécuter au moins 10 000 parties sans état impossible;
- les mêmes seeds reproduisent les mêmes simulations;
- aucune règle de consentement ne dépend de l'UI;
- STOP/retrait de consentement n'entraîne jamais de pénalité automatique;
- les médias ne sont jamais incorporés à l'historique analytique.


# Normalisation des règles restantes

## Seuil de récupération
Convention V1:
recovery_available = current_pa <= 20% de initial_pa.

Le seuil est calculé sur les PA initiaux de la session, pas sur le maximum historique atteint.
Si initial_pa=100, récupération disponible à 20 PA ou moins.

## PA
- minimum: 0
- aucun plafond supérieur
- aucune dette
- toute dépense est bornée par les PA disponibles
- une dépense qui doit amener sous zéro amène exactement à zéro
- les gains de récupération peuvent dépasser initial_pa

## Baisse du niveau 🌶️ et cartes déjà en main
Règle normalisée:
- chili_unlocked = plafond historique débloqué;
- chili_active = plafond actuellement souhaité;
- une baisse de chili_active ne détruit ni ne remplace les cartes déjà en main;
- au moment de jouer, seules les variantes <= chili_active sont normalement disponibles;
- si une carte n'a plus aucune variante compatible avec chili_active, elle reste en main mais devient temporairement injouable;
- le joueur peut déplacer son verrou normalement;
- lorsque chili_active remonte, les variantes redeviennent accessibles;
- Recovery conserve son exception explicite et peut dépasser chili_active.

Cette règle évite qu'une baisse d'intensité soit contournée simplement parce qu'une carte avait été piochée avant.

## Changement de contexte
Même principe:
- une carte peut devenir temporairement injouable;
- elle n'est pas automatiquement défaussée;
- DrawEngine ne pioche que des cartes actuellement éligibles;
- si le contexte redevient compatible, la carte redevient jouable.

Si toute une main devient injouable à cause d'un changement explicite de contexte, le moteur autorise un REFRESH_CONTEXTUEL gratuit des seules cartes devenues impossibles.
Ce refresh n'est pas un mulligan stratégique et est journalisé séparément.

## Main et verrou
- taille cible: 4;
- maximum un verrou;
- verrou déplaçable entre les rounds;
- carte verrouillée jouable;
- lorsqu'elle est engagée, le verrou disparaît;
- aucun verrou sur carte engagée/défausse/épuisée;
- refill uniquement après fermeture complète du round.

## Cycle de carte
POOL -> HAND -> ENGAGED -> DISCARD.
DISCARD -> HAND si repiochée faute de variété.
DISCARD -> EXHAUSTED uniquement lorsqu'elle est rejouée comme action de défausse et effectivement exécutée.
ENGAGED -> DISCARD après résolution, même en cas de renoncement stratégique.
Un STOP/retrait de consentement peut retirer la carte de la session selon la nouvelle compatibilité du profil, sans la qualifier d'EXHAUSTED.

## Égalité
- aucune perte de PA due à l'écart;
- aucune enchère PA pour départager;
- négociation via défausse/répétitions;
- un joueur finit par concéder ou les deux abandonnent le round;
- si aucun accord, aucune action principale n'est imposée;
- les deux cartes engagées suivent néanmoins leur cycle normal vers DISCARD à la clôture.

## Renoncement stratégique
Le gagnant peut renoncer à son action.
- coût d'écart déjà payé conservé;
- carte va en défausse;
- aucune pénalité additionnelle;
- événement distinct STRATEGIC_RENUNCIATION;
- ne doit jamais être confondu avec CONSENT_STOP.

## Corruption
Une proposition de corruption est une liste ordonnée:
CorruptionOffer:
- offered_by
- objective: OWN_INITIAL_ACTION | INVERT_WINNING_ACTION
- bid_pa
- discard_actions[]
- repetitions[]
- visibility_per_item: VISIBLE | MYSTERY
- proposed_order

Les actions de défausse ne donnent aucune puissance d'enchère.
Seuls les PA comptent pour dépasser une enchère.

## Exécution partielle
Pour chaque ActionPromise:
- PROPOSED
- ACCEPTED
- PERFORMED
- SKIPPED
- STOPPED

Seul PERFORMED applique StateEffect et peut épuiser une carte de défausse.
SKIPPED/STOPPED ne l'épuisent pas.
Les statistiques distinguent SKIPPED stratégique/ordinaire d'un STOP de consentement.

## Recovery
Entre deux duels seulement.
RecoveryGate:
- joueur <=20% initial_pa;
- aucune recovery depuis le dernier duel normal.

Source de carte:
- HAND
- DISCARD
- CATALOG

Une seule action principale choisie par le joueur en récupération.
Le partenaire peut:
- ACCEPT
- ACCEPT_WITH_ONE_DISCARD_CONDITION
- REFUSE

Gain:
somme des valeurs personnelles du joueur en récupération pour les rôles qu'il réalise réellement.
Aucun gain pour une action non réalisée.
Aucune valeur du partenaire dans le calcul.

Après Recovery:
- recovery gate fermé;
- un duel normal doit être clôturé avant nouvelle Recovery.

## Remontée commune
Si les deux joueurs satisfont le seuil de récupération:
- proposition entre rounds;
- montant choisi d'un commun accord;
- même montant ajouté aux deux;
- aucune carte;
- aucun événement d'audace;
- nombre d'utilisations illimité;
- événement MUTUAL_PA_EXTENSION.

## Fin de session
La session se termine uniquement par décision humaine explicite ou fermeture technique sauvegardable.
PA=0 n'est jamais une condition automatique de fin.
Durée indicative atteinte n'est jamais une condition automatique de fin.

## Mode discret
Le modèle de domaine contient la vérité complète.
Une VisibilityProjection construit ce que chaque client peut voir.
Ne jamais envoyer au client adverse une donnée cachée puis simplement la masquer graphiquement lorsque le backend peut l'éviter.

PublicState et PrivatePlayerState sont des DTO distincts.

## Commit / reveal deux appareils
Pour les décisions simultanées:
1. client choisit;
2. produit commitment = hash(session_round + player + choice_payload + nonce);
3. serveur reçoit commitment;
4. quand les deux commitments existent, chaque client révèle payload+nonce;
5. serveur vérifie le hash;
6. résolution.

Le protocole ne remplace pas les contrôles d'autorisation serveur.

## Reconnexion
À la reconnexion:
- récupérer dernier EventLog confirmé;
- reconstruire projection publique;
- récupérer état privé du joueur autorisé;
- reprendre à l'étape exacte de la machine d'état;
- aucune nouvelle pioche/enchère ne doit être générée par simple reconnexion.

## Idempotence
Toute commande réseau mutante porte command_id unique.
Une commande rejouée après timeout doit retourner le même résultat et ne jamais débiter deux fois les PA.

# Ce qui reste volontairement paramétrable

Les paramètres suivants appartiennent à BalanceConfig et non au code:
- initial_pa
- recovery_threshold_ratio (défaut structurel 0.20)
- gap_cost_curve
- gap_cost_cap
- chili_unlock_costs
- DrawEngine weights
- anti-repeat decay
- style distributions
- minimum evidence thresholds pour profils finaux

Ils pourront être modifiés après simulation sans migration du moteur.

# État de la spécification

Architecture fondamentale: figée pour prototype.
Règles de cycle/round: normalisées.
Consentement/profil: normalisés.
Format catalogue: défini.
Synchronisation: protocole cible défini.
Équilibrage numérique: à calibrer par simulation.
Contenu éditorial: extensible et encore à enrichir.
UI visuelle: volontairement différée.
