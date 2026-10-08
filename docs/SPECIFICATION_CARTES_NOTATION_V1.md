# ENCHAIRE / app-adulte — spécification des cartes et de leur notation

**Version du document :** 1.4  
**Date :** 7 octobre 2026  
**Public visé :** Codex et développeurs du projet `app-adulte`  
**Statut :** spécification normative prête pour implémentation ; les 17 questions initialisent les 65 cartes V4 et toutes leurs variantes/stades scoreables. Couverture vérifiée : **65/65 OK, 0 PARTIEL, 0 MANQUANT**.

> AVERTISSEMENT D'INTÉGRATION
>
> Ce document sépare strictement les règles validées, les données effectivement retrouvées et les informations indisponibles. Codex ne doit pas transformer une hypothèse, un exemple ou un élément marqué `À CONFIRMER` en donnée de production.

## 1. Objet

Le système doit :

1. créer un profil initial au moyen de 17 questions générales ;
2. convertir les réponses en valeurs PA sur des tags de préférence ;
3. calculer une valeur initiale pour chaque carte encore inconnue à partir de ses tags principaux et secondaires ;
4. appliquer les exclusions comme des veto, hors calcul numérique ;
5. apprendre ensuite une valeur propre à chaque carte à partir de son utilisation réelle en partie ;
6. conserver séparément consentement, préférences, contraintes techniques et données de session.

Le questionnaire n'est pas la source de vérité du profil. Les tags et les valeurs du profil sont la source de vérité ; le questionnaire ne fait que les initialiser. Il doit rester piloté par les données pour permettre l'ajout ultérieur d'une question, d'un tag ou d'une carte sans modifier le moteur.

## 2. Niveaux de certitude

Les mentions suivantes sont normatives dans tout le document :

- **VALIDÉ** : décision explicitement confirmée dans les conversations de conception.
- **SOURCE PROJET** : comportement retrouvé dans le projet local antérieur ; il ne devient normatif que s'il ne contredit pas une règle VALIDÉE.
- **PARTIEL** : information confirmée mais catalogue incomplet.
- **À CONFIRMER** : information absente des sources accessibles ; Codex ne doit pas l'inventer.
- **EXEMPLE** : illustration non normative.

En cas de conflit : `VALIDÉ > catalogue V4 canonique > SOURCE PROJET > hypothèse`. Une règle `À CONFIRMER` doit provoquer une erreur de validation de contenu ou le blocage explicite de la fonctionnalité concernée, jamais une valeur implicite silencieuse.

## 3. Règles validées

### 3.1 Réponses d'initialisation

| Réponse affichée | Valeur | Sémantique |
|---|---:|---|
| J'adore | 5 PA | forte préférence |
| Ça me plaît | 12 PA | préférence positive |
| Je ne sais pas | 20 PA | absence d'information, pas une exclusion |
| Exclu | aucune valeur numérique | veto explicite et persistant |

**VALIDÉ :** toute ancienne valeur d'initialisation `3/8/20` est obsolète et doit être migrée vers `5/12/20` pour les nouveaux profils. La migration des profils déjà créés n'a pas été spécifiée ; voir § 12.

### 3.2 Direction

Le vocabulaire canonique reste `FAIRE`, `RECEVOIR`, `MUTUEL`, `SOLO` et `SIMULTANE` selon la carte.

Pour une question directionnelle :

- `FAIRE` = moi qui réalise l'action ;
- `RECEVOIR` = l'autre qui réalise l'action sur moi.

Les deux valeurs sont indépendantes. Une préférence dans un sens ne doit pas autoriser ni noter automatiquement l'autre sens. La direction réellement jouée, après une éventuelle inversion, est celle qui doit être enregistrée pour l'apprentissage.

### 3.3 Calcul initial d'une carte

Pour une carte jamais jouée ou ne possédant pas encore assez d'historique propre :

```text
score_initial = somme(valeur_PA(tag_principal) × 1,0)
              + somme(valeur_PA(tag_secondaire) × 0,5)
```

**EXEMPLE validé :** un tag principal valant 5 et un tag secondaire valant 12 produisent `5 × 1 + 12 × 0,5 = 11`.

Règles associées :

- le calcul par tags est un **prior d'initialisation**, pas une formule à réappliquer en permanence ;
- seuls les tags de préférence notables participent au calcul ;
- directions, zones, contexte, matériel, exigences techniques et données de session ne valent jamais des PA par eux-mêmes ;
- `Exclu` n'entre jamais dans une somme : c'est un veto ;
- l'apprentissage d'une carte précise ne doit pas modifier brutalement toutes les cartes qui partagent ses tags.

### 3.4 Veto d'exclusion

Une carte ou une variante est inéligible pour un joueur si un de ses tags de préférence applicables, dans la direction et la zone applicables, est exclu. Le veto reste prioritaire sur :

- le score initial ;
- l'historique favorable de la carte ;
- la pondération de tirage ;
- une inversion de direction ;
- une combinaison avec d'autres cartes.

Une exclusion ne peut être levée que par une action manuelle explicite du joueur. Elle n'est jamais modifiée par l'apprentissage automatique.

### 3.5 Comparaison des cartes

La conversation valide la **somme pondérée brute** dans l'exemple, mais ne tranche pas explicitement la normalisation entre cartes ayant un nombre différent de tags. Par conséquent :

- calculer et stocker `score_initial_brut` selon la formule validée ;
- ne pas introduire de moyenne pondérée sans décision produit ;
- si un tri entre cartes exige une valeur comparable, exposer séparément `poids_total` et marquer l'algorithme de classement `À CONFIRMER`.

## 4. Modèle de données minimal

```yaml
CardDefinition:
  stable_id: string
  content_version: integer
  title: string
  description: string|null
  enabled: boolean
  directions: [FAIRE|RECEVOIR|MUTUEL|SOLO|SIMULTANE]
  variants: [CardVariant]
  metadata: object

CardVariant:
  stable_id: string
  title: string
  action_text: string
  details_text: string|null
  chili_level: integer|null
  engagement_level: integer|null
  primary_preference_tags: [string]
  secondary_preference_tags: [string]
  zones: [string]
  directions: [string]
  technical_requirements: [TechnicalRequirement]
  state_effects: [StateEffect]
  metadata: object
  enabled: boolean

ProfilePreference:
  profile_id: string
  tag_id: string
  role: GENERAL|FAIRE|RECEVOIR|MUTUEL|SOLO|OBSERVER|SIMULTANE
  zone_id: string|null
  pa: number|null
  excluded: boolean
  source: INITIAL_QUESTIONNAIRE|AUTO_LEARNED|MANUAL_CUSTOMIZED

PracticeConsent: # LEGACY, conservé uniquement pour relire les données existantes
  profile_id: string
  practice_tag_id: string
  role: GENERAL|FAIRE|RECEVOIR|MUTUEL|SOLO|OBSERVER|SIMULTANE
  zone_id: string|null
  status: UNKNOWN|ALLOWED|EXCLUDED
  source: MANUAL_EXPLICIT|SESSION_EXPLICIT

CardRatingState:
  profile_id: string
  card_id: string
  variant_id: string|null
  role: string
  initial_score: number|null
  current_estimate: number|null
  excluded: boolean
  observation_count: number
  evidence: object
  source: TAG_PRIOR|AUTO_LEARNED|MANUAL_CUSTOMIZED
```

Contraintes :

- identifiants stables, non dérivés des libellés ;
- une variante contient tous les tags nécessaires à son évaluation ;
- les tags principaux et secondaires sont explicitement séparés ;
- aucune direction ni zone n'est déduite d'un titre ;
- les exigences matérielles ou techniques restent distinctes des préférences ;
- `PracticeConsent` n'intervient plus dans l'éligibilité et reste uniquement
  sérialisé pour compatibilité avec les données existantes ;
- `ProfilePreference.excluded=true` est l'unique veto permanent du profil ;
- toute pratique non exclue peut être proposée si les autres règles de jeu le permettent ;
- le joueur peut toujours refuser ou utiliser STOP sans créer automatiquement une exclusion ;
- une nouvelle carte peut être initialisée sans nouvelle question si ses tags sont déjà couverts.

## 5. Questionnaire initial — définition validée et mapping technique

Chaque question accepte les quatre réponses du § 3.1. Les questions directionnelles recueillent deux réponses indépendantes. Une question générale peut écrire vers plusieurs préférences plus précises lorsqu'un lien sémantique raisonnable existe : chaque écriture est alors uniquement un **prior de préférence** de source `INITIAL_QUESTIONNAIRE`. Elle ne constitue ni la preuve d'une envie précise, ni une autorisation, ni un `PracticeConsent`.

| # | Libellé/famille validé | Axes indépendants | Écritures exactes (`tag_id`, rôle) |
|---:|---|---|---|
| 01 | Câlins | Général / MUTUEL | `calin`, `contact_corps`, `frotter` en `MUTUEL` |
| 02 | Baisers | Faire / Recevoir | `embrasser`, respectivement `FAIRE` et `RECEVOIR` |
| 03 | Jeux de mains | Faire / Recevoir | `main`, respectivement `FAIRE` et `RECEVOIR` |
| 04 | Jeux de bouche | Faire / Recevoir | `bouche`, respectivement `FAIRE` et `RECEVOIR` |
| 05 | Nudité | Moi / Mon-ma partenaire | `nudite`, `enlever`, `sous_vetements`, `striptease`, `tenue`, respectivement `FAIRE` (moi concerné) et `RECEVOIR` (partenaire concerné) |
| 06 | Zones intimes | Toucher / Être touché | `jeu_intime`, `masturbation`, `doigts`, `facesitting`, `ejaculation`, `pieds`, respectivement `FAIRE` et `RECEVOIR` |
| 07 | Sexe oral | Faire / Recevoir | `oral`, respectivement `FAIRE` et `RECEVOIR` |
| 08 | Pénétration | Faire / Recevoir | `penetration_vaginale` et `vaginal`, respectivement `FAIRE` et `RECEVOIR` ; `vaginal` est ici un prior anatomique réutilisable, pas une assimilation de toute pratique à la pénétration |
| 09 | Pratiques anales | Faire / Recevoir | `anal`, respectivement `FAIRE` et `RECEVOIR` |
| 10 | Plaisir en solo | Moi / Voir mon-ma partenaire | `masturbation`, respectivement `SOLO` et `OBSERVER` ; la résolution spéciale de la carte 021 est définie au § 8.2 |
| 11 | Jouets / accessoires | Sur mon-ma partenaire / Sur moi | `sextoy`, respectivement `FAIRE` et `RECEVOIR` |
| 12 | Jeux physiques | Faire / Recevoir | `frapper`, `tirer`, `maintien_cou`, `temperature`, `texture`, respectivement `FAIRE` et `RECEVOIR` |
| 13 | Contrôle / lâcher-prise | Prendre le contrôle / Laisser le contrôle à l'autre | `controle`, `ordres`, `position`, `attacher`, `immobiliser`, `privation_sensorielle`, `privation_parole`, `supplier`, `degradant`, respectivement `FAIRE` et `RECEVOIR` |
| 14 | Jeux de rôle / mise en scène | Général | `jeu_role` en `MUTUEL`; `simuler`, `deguisement`, `danser`, `paroles_coquines` en `GENERAL` |
| 15 | Se montrer / regarder | Me montrer / Regarder mon-ma partenaire | Me montrer : `etre_regarde`, `photo`, `video` en `FAIRE`. Regarder : `regarder`, `photo`, `video`, `contenu_adulte` en `RECEVOIR`. Les deux axes alimentent aussi `photo_mutuelle` et `video_mutuelle` en `MUTUEL` selon la règle prudente ci-dessous. |
| 16 | Surprise / découverte — « Ne pas savoir exactement ce que mon/ma partenaire me réserve » | Général | `surprise_decouverte`, `nourriture`, `boisson` en `GENERAL` |
| 17 | Lieux inhabituels / prise de risque — « Jouer dans un endroit inhabituel ou avec un peu de risque d'être surpris » | Général | `lieu_inhabituel`, `lieu_expose`, `douche_partagee`, `bain_partage` en `GENERAL` |

Les identifiants ci-dessus sont les identifiants canoniques exacts de la couche de préférences. Ils conservent l'orthographe ASCII déjà utilisée par la V4 (`controle`, `etre_regarde`, etc.). `surprise_decouverte` est un axe de profil sans consommateur dans les 65 cartes actuelles ; sa présence permet de conserver fidèlement la réponse Q16 sans modifier le catalogue V4. `photo_mutuelle` et `video_mutuelle` restent des préférences scoreables distinctes des médias individuels.

Pour Q15, le prior composé d'un profil est calculé séparément pour `photo_mutuelle` et `video_mutuelle` à partir de ses deux réponses : `EXCLU` si l'un des deux axes est `EXCLU`, sinon la valeur la plus prudente `max(PA_me_montrer, PA_regarder)`. Cette agrégation ne vaut pas consentement média. En partie, les deux profils doivent en outre passer la résolution `MUTUEL` du § 8.2.

**Règle de sécurité normative :** les écritures élargies ci-dessus sont des estimations initiales et rien de plus. Une réponse positive ne crée aucun objet de consentement. Une exclusion détaillée, un veto de zone et une impossibilité technique restent prioritaires. Une pratique non exclue peut être proposée, mais le joueur peut toujours la refuser ou utiliser STOP. La personnalisation explicite d'un tag précis remplace son prior général sans réécrire les autres tags issus de la même question. Les exclusions temporaires de session seront définies ultérieurement.

Les liens sont déclarés exhaustivement dans les données du questionnaire : aucune ressemblance de nom et aucun héritage implicite parent → enfant ne sont permis. Le même PA peut donc initialiser plusieurs tags, mais le moteur peut ensuite apprendre et personnaliser chacun de ces tags et chaque carte indépendamment.

**Règle de versionnement :** le questionnaire V1 comporte 17 questions ; 25 est un plafond de conception et non un objectif. Les nouvelles questions doivent être ajoutables par données. Un profil existant reçoit les nouveaux tags comme « non renseignés » et n'est pas obligé de recommencer l'ensemble du questionnaire.

## 6. Contrat proposé pour les questions

Ce contrat est exploitable ; ses contenus doivent être remplis depuis le mapping validé, sans déduction automatique.

```yaml
ProfileQuestion:
  stable_id: string
  questionnaire_version: integer
  order: integer
  label: string
  help_text: string|null
  response_scale: PA_5_12_20_EXCLUDED
  axes:
    - axis_id: string
      role: GENERAL|FAIRE|RECEVOIR|MUTUEL|SOLO|OBSERVER|SIMULTANE
      label: string|null
      writes:
        - tag_id: string
          zone_id: string|null
          weight: 1.0
          merge_strategy: null|MOST_RESTRICTIVE
  enabled: boolean
```

Lors de la soumission :

```text
pour chaque question
  pour chaque axe répondu
    pour chaque cible explicitement déclarée dans axis.writes
      si réponse == EXCLU
        écrire excluded=true, pa=null
      sinon
        écrire excluded=false, pa={5|12|20}
```

Si plusieurs axes de la même question alimentent une cible composée, son `merge_strategy` doit être déclaré. Q15 utilise `MOST_RESTRICTIVE` : `EXCLU` domine, puis `20`, `12`, `5`. Toutes les autres cibles de la V1 ont une source unique par rôle. Une nouvelle collision non accompagnée d'une stratégie explicite fait échouer la validation.

Une question ne doit écrire que vers les tags énumérés explicitement dans ses données. Aucun héritage implicite parent → enfant n'est autorisé. L'ajout de plusieurs `writes` à un axe n'ajoute aucune relation d'équivalence entre les tags concernés.

## 7. Cycle de vie de la note d'une carte

### 7.1 État initial

1. Vérifier les veto et exigences techniques.
2. Résoudre la direction et la variante applicables.
3. Récupérer les valeurs de profil des tags principaux et secondaires.
4. Calculer `score_initial_brut` avec les poids `1,0` et `0,5`.
5. Stocker ce score avec `source=TAG_PRIOR`.

### 7.2 Après utilisation en partie

La carte acquiert progressivement sa propre information. La valeur effective doit distinguer :

- préférence déclarée : le prior construit par questionnaire/tags ;
- comportement observé : exposition, attraction, acceptation et résistance ;
- valeur propre effective de la carte : estimation utilisée lorsque suffisamment de preuves existent.

L'historique doit être indexé au minimum par profil, carte, variante et rôle effectif. Une carte réversible conserve deux historiques indépendants pour `FAIRE` et `RECEVOIR`.

### 7.3 Signaux retrouvés dans la source projet

La source projet antérieure définit les signaux suivants, compatibles avec les décisions validées :

- exposition : carte réellement disponible dans la main ;
- attraction : carte jouée ou verrouillée ;
- acceptation : carte gagnante ou conservée dans le compromis final accepté ;
- résistance explicite : modification recherchée, inversion recherchée, défense finale ou évitement cohérent ;
- une carte simplement ignorée n'ajoute aucune résistance ;
- un STOP ou un résultat non accepté n'ajoute aucune preuve ;
- seuls les rôles finaux, après inversion, alimentent les statistiques.

Formule retrouvée :

```text
attractionRelative = attraction / exposition
acceptanceRelative = acceptance / resultOccurrences
resistanceRelative = resistance / resultOccurrences

tendance = 0,5 × attractionRelative
         + 0,5 × acceptanceRelative
         - résistanceRelative
```

Une division sans observation vaut zéro. La source projet conserve une fenêtre des 20 dernières observations pertinentes par clé, avec les cumuls historiques en parallèle.

### 7.4 Ajustement progressif retrouvé dans la source projet

La source projet propose les amplitudes suivantes :

- tendance très positive : `-1 PA` ;
- tendance positive : `-0,5 PA` ;
- stable : `0` ;
- résistance notable : `+0,5 PA` ;
- résistance forte : `+1 PA`.

Seul un mouvement vers un PA plus faible est modulé par le piment moyen : multiplicateur `0,4`, `0,6`, `0,8` ou `1`.

Une proposition de changement exige, dans la source projet :

- franchissement d'une catégorie ;
- 10 occurrences équivalentes ;
- 3 occurrences de confirmation ;
- 20 nouvelles occurrences si la valeur vient d'une personnalisation manuelle ;
- après refus, 20 nouvelles occurrences avant une proposition équivalente.

Ces seuils proviennent du moteur local antérieur. Ils sont **SOURCE PROJET**, pas une nouvelle décision issue de la conversation actuelle. Ils peuvent être conservés pour compatibilité, mais doivent être isolés dans une configuration testable.

### 7.5 Prior puis valeur propre

Implémentation attendue :

```text
si excluded(card, variante, rôle, zone)
  carte inéligible
sinon si historique propre insuffisant
  valeur_effective = score_initial_brut
sinon
  valeur_effective = estimation_propre_carte
```

Le seuil exact à partir duquel l'estimation propre remplace ou mélange le prior n'a pas été explicitement validé dans les conversations accessibles. Ne pas inventer un lissage bayésien, une moyenne ou un coefficient de mélange. Réutiliser le système de propositions de la source projet ou demander une décision produit.

## 8. Catalogue V4 fourni

Le contenu intégral du catalogue V4 a été fourni le 7 octobre 2026. Il contient exactement **65 cartes**, numérotées sans interruption de 001 à 065. Les décisions présentes dans ce catalogue priment sur les formulations antérieures.

| Élément | Donnée confirmée |
|---|---|
| Stimulation des tétons | carte supprimée ; `poitrine` reste une zone d'autres cartes |
| Masturbation solo | carte `MUTUEL` : chacun se masturbe soi-même en même temps |
| État des tenues | information joueur ; possibilité d'un pop-up pour resynchroniser le nombre de vêtements de chacun |
| Anal | conserve trois stades |
| Strip-tease | la V4 fournie définit finalement 3 stades ; cette donnée plus récente remplace l'ancienne décision « deux stades » |
| Simulation, stade 3 | ajoute gémissements et, si nécessaire, bruits de l'acte simulé |
| Doigter vaginal | trois niveaux : 1 doigt → 2 doigts → à volonté ; directions à distinguer |
| Doigter anal | trois niveaux : 1 doigt → 2 doigts → à volonté ; directions à distinguer |
| Sextoys | familles présentes : Sextoy, Masturbation avec sextoy, Masturbation mutuelle avec sextoy, Contrôle du jouet à distance |
| Variantes sextoy | vaginales, anales, phallus ; la carte générale comprend aussi bouche |
| Photo | niveaux Suggestive → Osée → Sans détour |
| Vidéo | niveaux Suggestive → Osée → Sans détour |
| Photo mutuelle / Vidéo mutuelle | préférences distinctes ; ne pas déduire d'un simple consentement à envoyer |
| Privation visuelle | carte à durée de 3 tours, coût de 3 PA à chaque joueur par tour |
| Privation auditive | carte à durée de 3 tours, coût de 3 PA à chaque joueur par tour |
| Privation de parole | carte à durée de 3 tours, coût de 3 PA à chaque joueur par tour |
| Entrave | carte à durée de 3 tours, sans coût |
| Maintien du cou | compteur 3 → 2 → 1 ; préférence distincte ; formulation non technique et sûre |
| Tirer doucement | compteur 3 → 2 → 1 |

### 8.0 Piment effectif et cartes à durée

Le niveau stocké sur chaque variante est son **piment de base**. Les niveaux
validés suivent cette lecture : 1 reste doux, 2 introduit une intensité
sensuelle nette, 3 correspond à une mise en scène ou une intensité soutenue,
et 4 couvre une pratique sexuelle explicite ou un engagement élevé. Le
catalogue V4 de cette version plafonne le piment effectif à 4.

Pour une carte qui utilise un paramètre de zone :

```text
piment_effectif = min(4, piment_de_base + modificateur_zone)
```

`modificateur_zone` vaut `+1` uniquement lorsque le jeu sélectionne ou impose
explicitement une zone sexuelle ou intime. Il vaut `0` pour une zone non
sexuelle et lorsque les joueurs choisissent librement la zone. Cette règle est
générale et ne dépend d'aucune carte particulière.

Une carte à durée reste active pendant que les autres actions continuent à se
jouer. Toutes les cartes à durée V4 durent exactement **3 tours**. La durée est
stockée dans `v4.duration_actions`; le domaine impose la constante canonique
`v4DurationCardActions = 3`. La liste actuelle est : Interdiction de toucher
(033), Entrave (034), Privation visuelle (035), Privation auditive (060),
Privation de parole / silence (061), Maintien du cou (062) et Tirer doucement
(063). Un simple objet de type ÉTAT n'est pas automatiquement une carte à
durée.

Ordre (032) impose de formuler et jouer réellement la dynamique d'ordre. La
personne ciblée reste libre d'exécuter ou non l'action demandée. Supplier (057)
impose de formuler et jouer la supplication ; ce qui est demandé reste librement
accordé ou refusé. Aucun de ces deux fonctionnements ne crée un consent gate et
leur piment décrit la dynamique elle-même.

### 8.1 Index complet des 65 cartes V4

Le détail intégral des actions, variantes, stades, zones, paramètres, états et règles particulières se trouve dans [CATALOGUE_CARTES_V4.txt](./CATALOGUE_CARTES_V4.txt), copie fidèle du contenu fourni. L'index suivant sert au contrôle rapide et ne remplace pas cette source.

| Nº | Carte | Type | Direction | Tags/préférences déclarés | Évolution |
|---:|---|---|---|---|---|
| 001 | CÂLIN | ACTION | MUTUEL | calin | Aucune |
| 002 | EMBRASSER | ACTION | FAIRE/RECEVOIR | embrasser | OUI — 3 stades |
| 003 | S'EMBRASSER | ACTION | MUTUEL | embrasser + lèvres + langue | OUI — 3 stades |
| 004 | JEU DE BOUCHE | ACTION GÉNÉRALE | FAIRE/RECEVOIR | bouche + zone compatible | Aucune |
| 005 | JEU DE MAIN | ACTION GÉNÉRALE | FAIRE/RECEVOIR | main + zone compatible | Aucune |
| 006 | RETIRER UN VÊTEMENT | ACTION | FAIRE/RECEVOIR | enlever | Aucune |
| 007 | RETIRER DEUX VÊTEMENTS | ACTION | FAIRE/RECEVOIR | enlever | Aucune |
| 008 | ÊTRE EN SOUS-VÊTEMENTS | ÉTAT | FAIRE/RECEVOIR | sous_vetements + ordre | Aucune |
| 009 | NU | ACTION | FAIRE/RECEVOIR | nudite | Aucune |
| 010 | STRIP-TEASE | ACTION | FAIRE/RECEVOIR | striptease | OUI — 3 stades |
| 011 | STRIP-TEASE COMPLET | ACTION | FAIRE/RECEVOIR | striptease + nudite | Aucune |
| 012 | CHOIX DE TENUE | ACTION | FAIRE/RECEVOIR | tenue + controle + ordre | Aucune |
| 013 | CHANGEMENT COMPLET DE TENUE | ACTION | FAIRE/RECEVOIR | tenue + deguisement | Aucune |
| 014 | CORPS CONTRE CORPS | ACTION | MUTUEL | contact_corps | Aucune |
| 015 | FROTTEMENTS HABILLÉS | ACTION | MUTUEL | frotter | Aucune |
| 016 | IMPOSER UNE POSTURE | ACTION | FAIRE/RECEVOIR | controle | Aucune |
| 017 | REPRODUIRE UNE POSTURE | ACTION | FAIRE/RECEVOIR | ordres | Aucune |
| 018 | SIMULATION | ACTION | FAIRE/RECEVOIR | simuler | OUI — 3 stades |
| 019 | MASTURBATION | ACTION | FAIRE/RECEVOIR | masturbation | OUI — 3 stades |
| 020 | MASTURBATION MUTUELLE | ACTION | MUTUEL | masturbation | Aucune |
| 021 | MASTURBATION SOLO | ACTION | MUTUEL | masturbation | Aucune |
| 022 | DOIGTER VAGINAL | ACTION | FAIRE/RECEVOIR | doigts + vaginal | OUI — 3 stades |
| 023 | DOIGTER ANAL | ACTION | FAIRE/RECEVOIR | doigts + anal | OUI — 3 stades |
| 024 | JEU INTIME | ACTION GÉNÉRALE | FAIRE/RECEVOIR | jeu_intime | Aucune |
| 025 | SEXE ORAL | ACTION | FAIRE/RECEVOIR | oral | OUI — 3 stades |
| 026 | 69 | ACTION | MUTUEL | oral | Aucune |
| 027 | PÉNÉTRATION VAGINALE | ACTION | FAIRE/RECEVOIR | penetration_vaginale | OUI — 3 stades |
| 028 | SEXE ORAL ANAL | ACTION | FAIRE/RECEVOIR | anal + oral | Aucune |
| 029 | CHOISIR UNE POSITION SEXUELLE | ACTION | FAIRE/RECEVOIR | controle + position | Aucune |
| 030 | FACESITTING | ACTION | FAIRE/RECEVOIR | facesitting | OUI — 3 stades |
| 031 | FROTTEMENT GÉNITAL | ACTION | MUTUEL | frotter | Aucune |
| 032 | ORDRE | ACTION | FAIRE/RECEVOIR | ordres | Aucune |
| 033 | INTERDICTION DE TOUCHER | CARTE À DURÉE | FAIRE/RECEVOIR | controle | Aucune |
| 034 | ENTRAVE | CARTE À DURÉE | FAIRE/RECEVOIR | attacher + immobiliser + contrôle | OUI — 3 stades |
| 035 | PRIVATION VISUELLE | CARTE À DURÉE | FAIRE/RECEVOIR | privation_sensorielle + vue | OUI — 3 stades |
| 036 | JEU DE TEMPÉRATURE | ACTION | FAIRE/RECEVOIR | temperature | OUI — 3 stades |
| 037 | FESSÉE | ACTION | FAIRE/RECEVOIR | frapper | OUI — 3 stades |
| 038 | DANSER | ACTION | FAIRE/RECEVOIR | danser | Aucune |
| 039 | PRENDRE LA POSE | ACTION | FAIRE/RECEVOIR | etre_regarde + controle | Aucune |
| 040 | DOUCHE À DEUX | ACTION | MUTUEL | douche_partagee | Aucune |
| 041 | BAIN À DEUX | ACTION | MUTUEL | bain_partage | Aucune |
| 042 | SEXTING | ACTION | MUTUEL | paroles_coquines + envoyer | Aucune |
| 043 | MESSAGE COQUIN | ACTION | FAIRE/RECEVOIR | paroles_coquines + envoyer | OUI — 3 stades |
| 044 | PHOTO | ACTION | FAIRE/RECEVOIR | photo + envoyer | OUI — 3 stades |
| 045 | PHOTO MUTUELLE | ACTION | MUTUEL | photo + envoyer | OUI — 3 stades |
| 046 | VIDÉO INTIME | ACTION | FAIRE/RECEVOIR | video + envoyer | OUI — 3 stades |
| 047 | VIDÉO MUTUELLE | ACTION | MUTUEL | video + envoyer | OUI — 3 stades |
| 048 | JEU DE RÔLE | ACTION | MUTUEL | jeu_role | Aucune |
| 049 | SEXTOY | ACTION | FAIRE/RECEVOIR | sextoy + tags de la variante | OUI — 3 stades |
| 050 | MASTURBATION AVEC SEXTOY | ACTION | MUTUEL | masturbation + sextoy + tags de la variante | OUI — 3 stades |
| 051 | MASTURBATION MUTUELLE AVEC SEXTOY | ACTION | MUTUEL | masturbation + sextoy + tags de la variante | OUI — 3 stades |
| 052 | CONTRÔLE DU JOUET À DISTANCE | ACTION | FAIRE/RECEVOIR | sextoy + contrôle + tags de la variante | OUI — 3 stades |
| 053 | CONTENU ADULTE PARTAGÉ | ACTION | MUTUEL | contenu_adulte + regarder | Aucune |
| 054 | SENSATION D'EXPOSITION | ACTION | MUTUEL | lieu_expose | Aucune |
| 055 | CHOIX D'ÉJACULATION | ACTION | FAIRE/RECEVOIR | ejaculation | Aucune |
| 056 | PAROLES DÉGRADANTES | ACTION | FAIRE/RECEVOIR | parole + degradant | OUI — 3 stades |
| 057 | SUPPLIER | ACTION | FAIRE/RECEVOIR | supplier + parole + contrôle | OUI — 3 stades |
| 058 | AILLEURS, EN PRIVÉ | ACTION | MUTUEL | lieu_inhabituel | Aucune |
| 059 | JEU DE TEXTURES | ACTION | FAIRE/RECEVOIR | texture | OUI — 3 stades |
| 060 | PRIVATION AUDITIVE | CARTE À DURÉE | FAIRE/RECEVOIR | privation_sensorielle + ouie | Aucune |
| 061 | PRIVATION DE PAROLE / SILENCE | CARTE À DURÉE | FAIRE/RECEVOIR | privation_parole + controle | Aucune |
| 062 | MAINTIEN DU COU | CARTE À DURÉE | FAIRE/RECEVOIR | maintien_cou + controle | OUI — 3 stades |
| 063 | TIRER DOUCEMENT | CARTE À DURÉE | FAIRE/RECEVOIR | tirer | OUI — 3 stades |
| 064 | DÉGUSTATION SENSUELLE | ACTION | FAIRE/RECEVOIR | nourriture + boisson | Aucune |
| 065 | FOOTJOB | ACTION | FAIRE/RECEVOIR | masturbation + pieds | Aucune |

### 8.2 Classification normative des préférences et audit de couverture

La table suivante est la classification exhaustive attendue par l'importeur. `P` signifie préférence principale, poids `1,0`; `S` signifie préférence secondaire, poids `0,5`; `NP` signifie donnée conservée mais ne portant aucun PA. Sauf delta explicite, la classification inscrite vaut pour tous les stades `S1/S2/S3`. Un stade ne crée jamais automatiquement un nouveau tag : son exclusion et son déblocage restent gérés par `stage_id`.

Dans la colonne Audit, `OK` signifie que le questionnaire V1 fournit un prior à toutes les préférences PA nécessaires à la portée indiquée. `PARTIEL` et `MANQUANT` sont conservés comme états de validation possibles, mais aucune ligne de la V4 n'y reste. Cette couverture ne vaut jamais consentement à exécuter l'action.

| Nº | Portée (variantes/stades) | P — poids 1,0 | S — poids 0,5 | NP — jamais des PA | Audit questionnaire V1 |
|---:|---|---|---|---|---|
| 001 | unique | `calin` | — | direction `MUTUEL` | OK — Q01 |
| 002 | S1, S2, S3; toute zone compatible | `embrasser` | — | zone, intensité, langue au S3 | OK — Q02 |
| 003 | S1, S2, S3 | `embrasser` | — | `levres` (zone), `langue` (technique), `MUTUEL` | OK — Q02, résolution mutuelle |
| 004 | chaque zone compatible | `bouche` | — | zone, geste choisi | OK — Q04 |
| 005 | chaque zone compatible | `main` | — | zone, geste choisi | OK — Q03 |
| 006 | unique | `enlever` | — | vêtement choisi, compteur tenue | OK — Q05 |
| 007 | unique | `enlever` | — | nombre de vêtements, compteur tenue | OK — Q05 |
| 008 | état unique | `sous_vetements` | `ordres` | état, compteur tenue, blocage d'autres cartes | OK — Q05 + Q13 |
| 009 | unique | `nudite` | — | état vestimentaire | OK — Q05 |
| 010 | S1, S2, S3 | `striptease` | — | niveau de déshabillage, compteur tenue | OK — Q05 |
| 011 | unique | `striptease` | `nudite` | compteur tenue | OK — Q05 |
| 012 | unique | `tenue` | `controle`, `ordres` | tenue choisie | OK — Q05 + Q13 |
| 013 | unique | `tenue` | `deguisement` | tenue/costume choisi | OK — Q05 + Q14 |
| 014 | unique | `contact_corps` | — | `MUTUEL` | OK — Q01 |
| 015 | unique | `frotter` | — | vêtements présents, `MUTUEL` | OK — Q01 |
| 016 | unique | `controle` | — | posture choisie, durée | OK — Q13 |
| 017 | unique | `ordres` | — | posture modèle | OK — Q13 |
| 018 | S1, S2, S3 | `simuler` | — | acte simulé, sons, intensité | OK — Q14 |
| 019 | S1, S2, S3 | `masturbation` | — | zone intime, intensité | OK — Q06 |
| 020 | unique | `masturbation` | — | simultanéité, zone intime | OK — Q06, résolution mutuelle |
| 021 | unique | `masturbation` | — | chacun agit sur soi, simultanéité | OK — Q10 avec résolution spéciale ci-dessous |
| 022 | S1, S2, S3 | `doigts`, `vaginal` | — | nombre de doigts, anatomie/compatibilité | OK — Q06 + Q08 |
| 023 | S1, S2, S3 | `doigts`, `anal` | — | nombre de doigts, anatomie/compatibilité | OK — Q06 + Q09 |
| 024 | chaque zone intime compatible | `jeu_intime` | — | zone, technique libre déjà acceptée | OK — Q06 |
| 025 | S1, S2, S3 non anal | `oral` | — | zone, intensité | OK — Q07 |
| 025 | S1, S2, S3 variante anale | `oral`, `anal` | — | zone anale, intensité | OK — Q07 + Q09 |
| 026 | unique | `oral` | — | position, zone intime, `MUTUEL` | OK — Q07, résolution mutuelle |
| 027 | S1, S2, S3 | `penetration_vaginale` | — | zone vaginale, rythme, intensité | OK — Q08 |
| 028 | unique | `oral`, `anal` | — | zone anale | OK — Q07 + Q09 |
| 029 | unique | `position` | `controle` | position choisie | OK — Q13 |
| 030 | S1, S2, S3 | `facesitting` | — | zones tête/bassin, durée, intensité | OK — Q06 |
| 031 | unique | `frotter` | — | zone intime, `MUTUEL` | OK — Q01 |
| 032 | unique | `ordres` | — | contenu de la consigne, mode distance | OK — Q13 |
| 033 | unique | `controle` | — | durée | OK — Q13 |
| 034 | S1 | `attacher` | `controle` | état, durée convenue, zones | OK — Q13 |
| 034 | S2 | `attacher` | `controle` | état, durée convenue, zones | OK — Q13 |
| 034 | S3 | `immobiliser` | `attacher`, `controle` | état, durée convenue, zones | OK — Q13 |
| 035 | S1, S2, S3 | `privation_sensorielle` | — | `vue` (modalité), état, coût, fin commune | OK — Q13 |
| 036 | S1, S2, S3; toute zone | `temperature` | — | zone, objet/source, intensité | OK — Q12 |
| 037 | S1, S2, S3 | `frapper` | — | `fesses` (zone fixe), rythme, intensité | OK — Q12 |
| 038 | unique | `danser` | — | style, durée | OK — Q14 |
| 039 | unique | `etre_regarde` | `controle` | pose, tenue courante | OK — Q15 + Q13 |
| 040 | unique | `douche_partagee` | — | douche disponible, `MUTUEL` | OK — Q17 |
| 041 | unique | `bain_partage` | — | bain disponible, `MUTUEL` | OK — Q17 |
| 042 | unique | `paroles_coquines` | — | `envoyer` (canal/action technique), appareil, réseau | OK — Q14 |
| 043 | S1, S2, S3 | `paroles_coquines` | — | `envoyer`, texte/audio, appareil, réseau | OK — Q14 |
| 044 | S1, S2, S3 | `photo` | — | `envoyer`, appareil, réseau, conservation média | OK — Q15; préférence seulement, pas consentement média |
| 045 | S1, S2, S3 | `photo_mutuelle` | — | `photo` (famille), `envoyer`, appareil, réseau, présence commune | OK — Q15, prior composé prudent |
| 046 | S1, S2, S3; variante avec ou sans zone | `video` | — | `envoyer`, zone, appareil, réseau, conservation média | OK — Q15; préférence seulement, pas consentement média |
| 047 | S1, S2, S3 | `video_mutuelle` | — | `video` (famille), `envoyer`, appareil, réseau, présence commune | OK — Q15, prior composé prudent |
| 048 | chaque scénario | `jeu_role` | — | scénario, présence préalable d'un roleplay | OK — Q14 |
| 049 | S1, S2, S3; variante bouche | `sextoy`, `bouche` | — | accessoire disponible, zone/compatibilité | OK — Q11 + Q04 |
| 049 | S1, S2, S3; variante anale | `sextoy`, `anal` | — | accessoire disponible, zone/compatibilité | OK — Q11 + Q09 |
| 049 | S1, S2, S3; variante vaginale | `sextoy`, `vaginal` | — | accessoire disponible, zone/compatibilité | OK — Q11 + Q08 |
| 049 | S1, S2, S3; variante phallus | `sextoy` | — | `phallus` (anatomie/compatibilité), accessoire disponible | OK — Q11 |
| 050 | S1, S2, S3; variante vaginale | `masturbation`, `sextoy`, `vaginal` | — | chacun sur soi, accessoire, compatibilité | OK — Q10 + Q11 + Q08, résolution mutuelle |
| 050 | S1, S2, S3; variante anale | `masturbation`, `sextoy`, `anal` | — | chacun sur soi, accessoire, compatibilité | OK — Q10 + Q11 + Q09, résolution mutuelle |
| 050 | S1, S2, S3; variante phallus | `masturbation`, `sextoy` | — | chacun sur soi, `phallus`, accessoire | OK — Q10 + Q11, résolution mutuelle |
| 051 | S1, S2, S3; variante vaginale | `masturbation`, `sextoy`, `vaginal` | — | chacun sur l'autre, accessoire, compatibilité | OK — Q06 + Q11 + Q08, résolution mutuelle |
| 051 | S1, S2, S3; variante anale | `masturbation`, `sextoy`, `anal` | — | chacun sur l'autre, accessoire, compatibilité | OK — Q06 + Q11 + Q09, résolution mutuelle |
| 051 | S1, S2, S3; variante phallus | `masturbation`, `sextoy` | — | chacun sur l'autre, `phallus`, accessoire | OK — Q06 + Q11, résolution mutuelle |
| 052 | S1, S2, S3; variante vaginale | `sextoy`, `vaginal` | `controle` | jouet télécommandable, réseau/portée, compatibilité | OK — Q11 + Q08 + Q13 |
| 052 | S1, S2, S3; variante anale | `sextoy`, `anal` | `controle` | jouet télécommandable, réseau/portée, compatibilité | OK — Q11 + Q09 + Q13 |
| 052 | S1, S2, S3; variante phallus | `sextoy` | `controle` | `phallus`, jouet télécommandable, réseau/portée | OK — Q11 + Q13 |
| 053 | unique | `contenu_adulte` | `regarder` | contenu disponible, écran, `MUTUEL` | OK — Q15 |
| 054 | unique | `lieu_expose` | — | lieu réel choisi, cadre privé, `MUTUEL` | OK — Q17 |
| 055 | chaque zone/manière | `ejaculation` | — | zone, manière, avaler/cracher, possibilité physiologique | OK — Q06 |
| 056 | S1, S2, S3 | `degradant` | — | `parole` (modalité), vocabulaire, intensité | OK — Q13 |
| 057 | S1, S2, S3 | `supplier` | `controle` | `parole` (modalité), texte prononcé | OK — Q13 |
| 058 | unique | `lieu_inhabituel` | — | lieu choisi, caractère privé, déplacement possible | OK — Q17 |
| 059 | S1, S2, S3; toute zone | `texture` | — | zone, matière disponible, intensité | OK — Q12 |
| 060 | état unique | `privation_sensorielle` | — | `ouie` (modalité), état, coût, fin commune | OK — Q13 |
| 061 | état unique | `privation_parole` | `controle` | état, coût, fin commune, commandes UI | OK — Q13 |
| 062 | S1, S2, S3 | `maintien_cou` | `controle` | cou (zone), compteur, geste sans serrer | OK — Q12 + Q13 |
| 063 | S1, S2, S3; toute zone compatible | `tirer` | — | zone, compteur, intensité | OK — Q12 |
| 064 | variante nourriture | `nourriture` | — | zone, aliment disponible, allergies/contraintes | OK — Q16 |
| 064 | variante boisson | `boisson` | — | zone, boisson disponible, allergies/contraintes | OK — Q16 |
| 065 | unique | `masturbation`, `pieds` | — | pieds (outil et identité), compatibilité anatomique | OK — Q06 |

Synthèse au niveau carte, en classant une carte selon sa variante la moins couverte : **65 OK**, **0 PARTIEL**, **0 MANQUANT**. Les 65 cartes, tous leurs stades et toutes les variantes scoreables décrites par la V4 ont au moins un prior calculable après réponse aux 17 questions. Aucune question 18–25 n'est nécessaire.

Règles de résolution nécessaires à cette table :

- un tag `GENERAL` s'applique aux rôles directionnels de la même personne sans créer de consentement ;
- une carte `MUTUEL` n'emploie jamais arbitrairement une seule réponse : elle résout les préférences nécessaires pour chacun des deux profils et conserve le détail des contributions ;
- pour 006–013, le rôle du tag vestimentaire désigne la personne dont la tenue change (`FAIRE` = moi concerné, `RECEVOIR` = partenaire concerné), même si le texte de l'action implique aussi un acteur ;
- pour 003 et 026, chaque joueur doit disposer de la préférence correspondante dans les sens qu'il exerce réellement ; si le moteur ne distingue pas les contributions, la résolution est `Unknown` ;
- pour 021, chaque joueur doit avoir `masturbation/SOLO`; l'axe `masturbation/OBSERVER` de chacun couvre le fait de voir l'autre. Les quatre valeurs sont nécessaires et les quatre exclusions sont des veto ;
- pour 019, 020, 051 et 065, `masturbation/FAIRE|RECEVOIR` provient de Q06; pour 021 et 050, `masturbation/SOLO|OBSERVER` provient de Q10. Les rôles ne sont pas interchangeables ;
- pour 050, chaque joueur doit avoir `masturbation/SOLO` et la préférence `sextoy` applicable à « sur moi ». Pour 051, il faut au contraire les rôles exercés sur l'autre, fournis par Q06 et Q11 ;
- `photo_mutuelle` et `video_mutuelle` sont initialisés par l'agrégation prudente de Q15, sans retomber dynamiquement vers `photo` ou `video` après personnalisation ;
- pour 053, chaque profil résout `contenu_adulte/RECEVOIR` et `regarder/RECEVOIR`, puisque les deux joueurs regardent le contenu partagé ;
- lorsqu'une carte offre des alternatives (`064`, ou les variantes de `049` à `052`), les tags des alternatives non choisies ne sont pas cumulés.

### 8.3 Registre canonique : préférence contre donnée non notée

Sont des préférences PA dans cette V4 uniquement les identifiants apparaissant en colonnes `P` ou `S` du § 8.2. Sont notamment non notés : `levres`, `langue`, `vue`, `ouie`, les zones anatomiques ordinaires, `phallus`, `envoyer`, niveaux d'intensité, stades, nombres de doigts, tenue courante, compteurs, coûts PA, durée, appareil, réseau, matériel, disponibilité d'un lieu, scénario, texte libre, effets d'état et métadonnées.

Une zone devient exceptionnellement une préférence quand elle définit la pratique et figure alors explicitement en `P` : `anal`, `vaginal` pour les variantes concernées, et `pieds` pour Footjob. Le tag composé `penetration_vaginale` est une préférence autonome; il n'est pas remplacé par le simple paramètre de zone `vaginale`.

Les chaînes éditoriales `contrôle` et `controle` sont normalisées vers l'unique identifiant `controle`. Les singuliers/pluriels ne sont pas fusionnés implicitement : `ordre` de l'ancien index est corrigé en `ordres`, conformément à la carte 032 et à la classification ci-dessus.


## 9. Catalogue V4 : contrat d'import canonique

Le fichier [CATALOGUE_CARTES_V4.txt](./CATALOGUE_CARTES_V4.txt) est la source éditoriale canonique disponible. L'importeur doit préserver, pour chacune des 65 cartes :

- identifiant stable et ordre ;
- version de contenu, titre et textes ;
- activation dans le deck ;
- direction(s) permise(s) ;
- toutes les variantes ;
- niveaux/stades et niveau de piment ou d'engagement disponible ;
- tags de préférence principaux ;
- tags de préférence secondaires ;
- zones ;
- contraintes techniques et matérielles ;
- effets d'état et coûts récurrents ;
- règles d'inversion ;
- métadonnées de migration/remplacement ;
- tout paramètre ou compteur propre à la carte.

Validation obligatoire du catalogue :

```text
nombre de cartes actives V4 == 65
stable_id unique pour chaque carte et variante
chaque variante scoreable possède >= 1 tag de préférence
chaque tag de préférence est principal ou secondaire, jamais implicite
chaque carte directionnelle définit ses rôles
chaque requirement référence un type connu
aucune carte supprimée ne revient dans le deck
aucune question n'est créée automatiquement à partir d'un tag technique
```

## 10. Algorithme d'initialisation de référence

```pseudo
function initializeCardRating(profile, card, variant, effectiveRole):
    applicable = resolveApplicablePreferenceTags(variant, effectiveRole)

    resolved = []
    for tag in applicable.primary + applicable.secondary:
        # Résolution : rôle exact, sinon GENERAL explicitement autorisé.
        # MUTUEL est résolu contribution par contribution selon le § 8.2;
        # il ne choisit jamais arbitrairement le profil ou le sens le plus favorable.
        preference = resolvePreference(profile, tag, effectiveRole, card.direction)
        if preference.excluded:
            return Excluded(tag.id)
        resolved.add(tag, preference)

    missing = [item.tag for item in resolved if item.preference is missing]
    if missing is not empty:
        return Unknown("préférences non renseignées", missingTagIds=missing.ids)

    raw = 0
    for item in resolved.primary:
        raw += item.preference.pa * 1.0
    for item in resolved.secondary:
        raw += item.preference.pa * 0.5

    return InitialRating(
        rawScore = raw,
        totalWeight = count(primary) + 0.5 * count(secondary),
        source = TAG_PRIOR
    )
```

`Unknown` n'est pas équivalent à `Exclu`. Le comportement produit lorsqu'une préférence requise est absente n'a pas été spécifié. Le choix sûr est de ne pas rendre automatiquement la carte éligible tant que la règle produit n'est pas validée.

Après soumission complète des 17 questions V1, `Unknown("préférences non renseignées")` ne doit se produire pour aucune des 65 cartes V4 ni pour une de leurs variantes/stades scoreables. Il reste nécessaire pour un ancien profil non migré, une future carte/tag, une donnée corrompue ou une personnalisation incomplète. `Unavailable` reste un résultat distinct lorsque les contraintes techniques, matérielles ou contextuelles échouent. `UnknownConsent` est retiré du flux actif.

L'ordre est normatif : rechercher tous les veto de profil connus avant de retourner `Unknown`. Ainsi, un tag manquant ne masque jamais une exclusion présente sur un autre tag. Les exigences techniques sont évaluées séparément et peuvent produire `Unavailable`, jamais une valeur PA. L'absence d'un ancien `PracticeConsent` ou son statut legacy ne bloque jamais la carte.

## 11. Tests d'acceptation minimaux

1. `principal=5`, `secondaire=12` donne un score brut de `11`.
2. Deux tags principaux à `5` et `12` donnent `17`.
3. Un tag secondaire exclu rend la carte inéligible ; il ne donne ni `0` ni `20`.
4. `FAIRE=5` n'initialise pas automatiquement `RECEVOIR`.
5. Une préférence générale « jeux de bouche » n'autorise pas implicitement une variante de sexe oral ou anal.
6. Une carte jamais jouée utilise le prior par tags.
7. Une observation sur la carte A ne change pas directement la note propre de la carte B partageant ses tags.
8. Une carte inversée alimente le rôle effectif final, pas son rôle natif.
9. Une carte ignorée n'ajoute pas de résistance.
10. Un STOP ou un résultat refusé n'ajoute pas d'acceptation.
11. Une exclusion ne peut pas être levée par l'apprentissage.
12. Une nouvelle question peut être ajoutée par données et les anciens profils conservent les cibles nouvelles comme non renseignées.
13. Une variante sans tag de préférence explicite échoue à la validation du catalogue.
14. Les coûts d'état, contraintes matérielles et niveaux physiques ne participent pas à la note de préférence.
15. Q05 initialise séparément `nudite`, `enlever`, `sous_vetements`, `striptease` et `tenue` avec le même prior de départ; personnaliser ensuite `striptease` ne modifie pas les quatre autres tags.
16. Q06 initialise `jeu_intime`, `masturbation/FAIRE|RECEVOIR`, `doigts`, `facesitting`, `ejaculation` et `pieds`, mais n'écrit ni `oral`, ni `anal`, ni `vaginal`, ni `sextoy`.
17. Q12 initialise `frapper`, `tirer`, `maintien_cou`, `temperature` et `texture`; un PA positif sur l'un d'eux ne crée aucun `PracticeConsent`.
18. Q13 initialise `controle`, `ordres`, `position`, `attacher`, `immobiliser`, `privation_sensorielle`, `privation_parole`, `supplier` et `degradant` dans le rôle correspondant.
19. La variante anale de 025 requiert `oral` et `anal`; une exclusion sur l'un ou l'autre est un veto.
20. Les trois stades de 037 gardent `frapper` en principal; `fesses` et l'intensité ne reçoivent aucun PA.
21. Le S3 de 034 utilise `immobiliser` en principal et `attacher`/`controle` en secondaires.
22. La variante `phallus` de 049 n'attribue aucun PA à l'anatomie `phallus`.
23. La variante vaginale de 049 utilise `sextoy` issu de Q11 et `vaginal` issu de Q08; une exclusion sur l'un ou l'autre est un veto.
24. Pour 064, la variante nourriture ne demande pas `boisson`, et réciproquement.
25. Pour 021, une exclusion `masturbation/SOLO` ou `masturbation/OBSERVER` de l'un des joueurs rend l'occurrence inéligible.
26. L'absence de `PracticeConsent`, ou un ancien statut `UNKNOWN`, ne bloque pas une carte dont les préférences sont renseignées et non exclues.
27. Un tag manquant et un autre tag exclu retournent `Excluded`, pas `Unknown`.
28. Chaque ligne/stade/variante du § 8.2 est chargée; tout tag non classé `P`, `S` ou `NP` fait échouer l'import.
29. Les 65 numéros 001–065 existent exactement une fois dans l'index et chacun possède au moins une ligne d'audit au § 8.2.
30. Après suffisamment d'historique propre, modifier un tag de profil ne réécrit pas rétroactivement `estimation_propre_carte`.
31. Q15 calcule `photo_mutuelle` et `video_mutuelle` avec `MOST_RESTRICTIVE`; `5` et `20` donnent `20`, et toute réponse `EXCLU` donne un veto.
32. Q16 initialise séparément `nourriture` et `boisson`; la variante 064 choisie n'exige jamais l'autre tag.
33. Q17 initialise `douche_partagee` et `bain_partage` comme priors de lieux intimes, sans ignorer la disponibilité technique réelle.
34. Un profil ayant répondu aux 17 questions avec des valeurs numériques possède toutes les préférences requises pour chaque ligne du § 8.2.
35. L'audit automatique compte exactement `65 OK`, `0 PARTIEL`, `0 MANQUANT`; le moindre écart fait échouer la validation de la spécification/catalogue.

## 12. Points non spécifiés — interdiction d'inventer

Les points suivants restent ouverts, sans empêcher le calcul initial des 65 cartes :

1. identifiants techniques stables des variantes et stades ; les cartes peuvent recevoir `card_001` à `card_065`, mais le catalogue ne fournit pas les identifiants des sous-éléments ;
2. normalisation éventuelle des scores entre cartes ayant des nombres de tags différents ;
3. politique UX lorsqu'un tag requis est absent sur un ancien profil ou une future extension ; le moteur retourne normativement `Unknown`, mais affichage, filtrage ou demande de précision restent à décider ;
4. seuil/méthode exacte de remplacement ou de mélange entre prior et note propre de carte ;
5. migration des profils existants initialisés avec l'ancienne échelle `3/8/20` ;
6. coexistence éventuelle d'une note propre à la carte et de l'apprentissage des préférences par tag ;
7. politique de partage ou de confidentialité réseau de la note propre à la carte ;
8. découpage éditorial officiel de la carte 064 en variantes nourriture/boisson. Le scoring les traite comme alternatives afin d'éviter d'exiger les deux, mais leurs `stable_id` restent à fournir.

Codex doit implémenter ces points derrière des interfaces/configurations, ou interrompre l'import avec un diagnostic clair, jusqu'à réception d'une décision ou d'une donnée canonique.

## 13. Sources consultées et écarts constatés

- Conversation « Conception dapp adulte suite » : échelle `5/12/20/Exclu`, poids principal/secondaire, calcul d'exemple, rôle de prior, questions 16 et 17.
- Conversation « Conception dapp adulte » : questions 1 à 5 et règles de granularité générale ; sa restitution antérieure de 06 à 10 est remplacée par la correction directe de l'utilisateur.
- Demande directe du 7 octobre 2026 : série validée 06 Zones intimes, 07 Sexe oral, 08 Pénétration, 09 Pratiques anales, 10 Plaisir en solo.
- Restitution directe de l'utilisateur : questions 11 à 15 et confirmation de l'ensemble des 17 questions.
- Aperçu du catalogue V3.2 dans une tâche antérieure : corrections de cartes reprises au § 8.
- Catalogue fourni par l'utilisateur : `ENCHAIRE — CATALOGUE DES CARTES RECONSTRUIT V4`, copié fidèlement dans [CATALOGUE_CARTES_V4.txt](./CATALOGUE_CARTES_V4.txt).
- Copie locale antérieure du projet : taxonomie V3 et moteur `profile_learning_v1`.

Écarts importants :

- la copie locale antérieure contient un catalogue V3 plus large ; la V4 fournie de 65 cartes est désormais prioritaire ;
- son moteur initialise encore `J'adore=3` et `Ça me plaît=8` ; ces valeurs doivent devenir `5` et `12` pour les nouveaux profils ;
- l'historique automatique ne contenait pas les questions 11 à 15 ; elles ont été rétablies directement par l'utilisateur ; leur mapping figure désormais au § 5 ;
- la V1.3 refusait tout mapping élargi pour Q12/Q16 et laissait 44 cartes `PARTIEL` ou `MANQUANT`. La présente passe corrige cette interprétation : les pratiques précises reçoivent des priors explicitement déclarés lorsqu'un lien sémantique raisonnable existe, sans création de consentement ;
- Q16 conserve en plus `surprise_decouverte` dans le profil, même si aucune carte V4 ne consomme directement cet axe.

## 14. État de finalisation et règle de livraison

Le mapping demandé et la classification principal/secondaire sont complets et normatifs. L'audit couvre les 65 cartes et toutes les variantes/stades explicitement décrits par la V4.

Vérification finale obligatoire :

- cartes V4 auditées : **65** ;
- cartes entièrement initialisables après les 17 réponses : **65 (100 %)** ;
- cartes `PARTIEL` : **0** ;
- cartes `MANQUANT` : **0** ;
- nouvelles questions nécessaires : **0** ; le questionnaire reste à **17/25** ;
- exceptions de calcul : uniquement `Exclu`/veto, contrainte technique rendant la variante indisponible, profil ancien/incomplet ou données invalides.

La spécification est donc **prête pour Codex**. L'implémentation doit charger les mappings explicites du § 5, la classification du § 8.2, utiliser `ProfilePreference.excluded` comme unique veto permanent du profil, puis utiliser les tags comme prior initial avant l'apprentissage propre à la carte du § 7. Les anciennes données `PracticeConsent` restent uniquement lisibles pour compatibilité et n'interviennent jamais dans l'éligibilité. Les décisions produit encore ouvertes au § 12 ne remettent pas en cause la couverture de notation.
