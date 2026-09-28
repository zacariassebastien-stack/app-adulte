# Phase 4 — protocole de simulation et équilibrage

## Périmètre

Le moteur de référence est `dcffdc82e7965122b634c75ef4555178a1289ba7`.
Les fichiers du domaine, des moteurs, du stockage et du catalogue sont inchangés.
Aucune interface Flutter, aucune règle de fin réelle et aucun profil humoristique
final ne sont ajoutés. Les données produites sont exclusivement synthétiques.

`lib/simulation/configuration.dart` sépare les profils de consentement, stratégies
composables, probabilités et limites. `SimulationRunner` orchestre les moteurs
réels Eligibility, Draw, Lifecycle, Duel, Auction, Corruption, Recovery, Intensity
et VisibilityProjection. `SimulationMetrics` agrège compteurs, histogrammes exacts,
fréquences et exemples bornés d'anomalies. `BalanceExperiment` exécute une
configuration nommée et conserve les mêmes seeds pour permettre une comparaison.
`tool/simulation_report.dart` transforme le JSON en tableaux Markdown.

## Reproduction

```sh
dart run tool/simulate.dart --sessions 1 --seed 410000 --rounds 50 --output .tooling/debug.json
dart run tool/simulate.dart --sessions 100 --output .tooling/benchmark100.json
dart run tool/simulate.dart --sessions 1000 --output .tooling/benchmark1000.json
dart compile exe tool/simulate.dart -o .tooling/simulate.exe
.tooling/simulate.exe --sessions 10000 --seed 410000 --output docs/simulation_baseline.json
dart run tool/simulation_report.dart
```

Sous Unix, utiliser un nom d'exécutable sans `.exe` et le préfixe `./`.
`--rounds`, `--actions`, `--scenario` et `--output` sont configurables.
`--scenario` accepte un identifiant exact de la matrice dans le JSON ; `all` est
la valeur par défaut. Un filtre vide ou un volume nul est rejeté.
Pour explorer les stratégies, probabilités, profils et tous les paramètres de
BalanceConfig, utiliser l'API Dart plutôt que modifier les moteurs :

```dart
final baseline = BalanceExperiment(name: 'BASELINE', config: const BalanceConfig());
final experiment = BalanceExperiment(
  name: 'EXPERIMENTAL_INITIAL_PA_120',
  config: const BalanceConfig(initialPa: 120),
);
// Pour chacun : run(catalog, sessions: 1000, seed: 410000,
//   scenarios: representativeScenarios(), policy: const DecisionPolicy());
```

Les courbes personnalisées implémentent `GapCostCurve` ; coûts 🌶️, cap,
`DrawWeights`, décroissance et distributions de style sont injectables via le
BalanceConfig existant. La main cible reste quatre dans cette phase.
Ces configurations expérimentales ne remplacent jamais la constante de production.

Une seed de session vaut `seedStart + index`, le scénario vaut `index % 27`.
Les générateurs de profils ont les seeds `2 * seed + 1` et `2 * seed + 2`,
distinctes du générateur des décisions. Les horodatages de commit sont fictifs et
déterministes. Même catalogue, version Dart, scénarios, configurations et seed
donnent exactement les mêmes métriques. Le champ `execution` contient la durée
mesurée et ne fait pas partie de cette égalité. Aucun hasard d'horloge n'est utilisé.

## Profils synthétiques

| Pool | Probabilité ACCEPTED par élément | Valeurs uniformes inclusives |
|---|---:|---:|
| CONSERVATIVE_POOL | 0,40 | 1–10 |
| BROAD_POOL | 0,90 | 1–20 |
| HIGH_AUDACITY_POOL | 0,95 | 10–20 |
| MIXED_POOL | 0,65 | 1–20 |

Parmi les autres statuts : un tiers EXCLUDED, un tiers DISCOVER, le reste UNSET.
Les valeurs GENERAL, FAIRE et RECEVOIR sont indépendantes ; une valeur attribuée
à un élément non accepté ne lui accorde aucune permission. Les exclusions
hiérarchiques restent appliquées par EligibilityEngine, sans correction du profil.
`SyntheticProfileSpec` permet de changer toutes ces probabilités et bornes.
Les goûts similaires utilisent les mêmes préférences pour les deux identifiants.
Les asymétries croisent pools, distributions de valeurs et modes ; elles ne
représentent aucune population réelle ni aucun diagnostic.

La matrice compte les onze couples de stratégies demandés, chacun en broad/broad
et dans un couple asymétrique, trois styles initialement au niveau 5, un couple
aux goûts identiques et BOLD+PA_SAVER contre CAUTIOUS+PA_SPENDER avec valeurs
hautes/basses. Elle est configurable sans produit cartésien exponentiel.

## Décisions artificielles, distinctes des règles

Les valeurs suivantes sont des hypothèses d'expérience, pas des paramètres
validés de comportement humain. Toutes les probabilités sont dans DecisionPolicy
et sérialisées dans chaque rapport. Les décisions conditionnelles ne sont tentées
que lorsque le moteur les permet.

| Décision | Probabilité de base |
|---|---:|
| Contre-enchérir / défendre | 0,30 / 0,40 |
| Proposer une montée / accord du partenaire | 0,12 / 0,70 |
| Baisse convenue | 0,02 |
| Tenter Recovery / refuser / demander une condition | 0,50 / 0,08 / 0,20 |
| STOP / action ignorée | 0,005 / 0,01 après absence de STOP |
| Poser un verrou / jouer la carte verrouillée | 0,15 / 0,25 |
| Corruption / acceptation | 0,08 / 0,50 |
| Extension / accord | 0,01 / 0,50 |
| Renoncement stratégique / changement de style | 0,01 / 0,01 |
| Cible inversion si autorisée | 0,20 |

PA_SAVER et AUCTION_PASSIVE multiplient contre/défense par 0,15 ; sinon
AUCTION_AGGRESSIVE par 2,5, sinon PA_SPENDER par 2. Priorité explicite dans une
composition. CHILI_STABLE multiplie la proposition par 0,1 et l'accord par 0,3 ;
sinon CHILI_CLIMBER multiplie la proposition par 4, PA_SPENDER par 2, PA_SAVER
par 0,25. RECOVERY_RISK multiplie la tentative de Recovery par 2. Les résultats
sont bornés à [0,1]. Les probabilités de base restent configurables, même à 0 ou 1.

La sélection attribue un bruit uniforme [0,5) à chaque choix. BOLD ajoute sa valeur,
CAUTIOUS la soustrait. VARIETY_SEEKER pénalise cinq fois les tirages déjà vus et
les tags sélectionnés auparavant. SPECIALIST ajoute 20 aux cartes partageant le
premier tag de la première carte du catalogue (famille fixée, sans permission ajoutée).
Les effets des stratégies composées s'additionnent. La variante examinée en premier
est la dernière variante éligible dans l'ordre éditorial.

Pour le commit, l'agent choisit le premier rôle volontaire ACTOR/BOTH accepté,
noté et non bloqué par un parent parmi les exigences de la variante. Il ne
fabrique pas de note à partir d'un élément absent. Les exigences RECEVOIR du
partenaire sont toujours évaluées ; une carte sans valeur de commit compatible
reste distincte d'une carte non éligible. Ce choix ne prétend pas couvrir toutes
les décisions de rôle que pourrait proposer l'UI future.

L'enchère vaut `floor(1 + PA * bidFraction * U)`, bornée aux PA disponibles,
avec `bidFraction = 0,08`. La défense vaut contre-enchère + 1 si payable.
L'inversion est tentée seulement si la variante est inversible et reste éligible
pour les rôles inversés ; les snapshots et le coût du duel initial sont conservés.
Une corruption porte sur une action éligible du discard, sans puissance numérique,
et ne change le choix final qu'après accord et réalisation. STOP interrompt la suite
de cette séquence, sans sanction supplémentaire.

Le proposant paie l'unité impaire d'une montée, le partenaire l'autre moitié.
Une baisse est modélisée comme une décision déjà convenue ; la main est conservée.
Une extension convenue ajoute 10 PA à chacun par le moteur Recovery. Une égalité
conserve ses coûts nuls ; les agents conviennent de passer au round suivant,
sans action arbitrairement gagnante. Un renoncement stratégique ferme seulement
le round sans nouveau duel et sans réinitialiser la disponibilité Recovery.

Recovery choisit uniformément une action autorisée, main/discard/catalogue ;
la condition éventuelle est la première action éligible distincte du discard.
Les effets de la première action sont appliqués avant de revalider la condition.
Une condition devenue impossible est ignorée, sans gain. Les gains ne concernent
que les rôles réellement accomplis. Les refus/STOP sont exclusivement techniques.

Le verrou ne renouvelle aucune carte : les autres cartes restent également en
main jusqu'à engagement. Le simulateur évite le verrou 75 % du temps si une
alternative existe. Il utilise LifecycleEngine pour le verrou, l'engagement,
le discard et l'épuisement. Le pool est l'absence de runtime state (aucune zone
POOL n'est ajoutée au modèle Phase 3). Les mains sont privées par joueur ;
l'épuisement d'un identifiant est partagé dans le contexte de session.

## Limites techniques et invariants

Valeurs par défaut : 50 rounds tentés, 5 000 étapes sémantiques, 100 tentatives
Recovery par session. `maxActions` compte les opérations de l'orchestrateur,
pas chaque événement élémentaire. Il peut interrompre un round incomplet.
Le garde-fou Recovery est supplémentaire au gate métier entre deux duels.
Aucune de ces limites ne passe dans LifecycleEngine comme règle de fin.

Une simulation se termine aussi techniquement si aucune sélection des deux
joueurs n'est possible ; elle ne déclare pas que la vraie session doit finir.
Les petits pools sont valides. Aucun consentement n'est accepté pour réparer un pool.

Contrôles actifs : PA non négatifs et bilan exact de toutes les dépenses/gains ;
zones uniques par joueur ; au plus un verrou en main ; main au plus quatre ;
aucune entrée tirée épuisée ou non éligible ; source de tirage pool/discard ;
consentement et contexte revalidés au commit et à l'exécution ; gate et
éligibilité Recovery ; enchères autorisées par AuctionEngine ; absence d'effet
hors COMPLETED ; neutralité PA du traitement STOP/refus ; aucune fin à zéro PA ;
projection publique sans PA ni cartes non révélées. Le mode debug/test lève une
exception avec seed, round et code à la première violation. Le mode collecte
peut conserver jusqu'à 100 exemples ; les compteurs ne sont pas tronqués.

## Dictionnaire des mesures

`counters` additionne les événements et volumes ; `distributions` fournit count,
moyenne, médiane exacte, min, max et histogramme ; `frequencies` détaille les IDs.
Les suffixes `.a` et `.b` distinguent les joueurs. Les seuils `firstAt*` sont des
numéros de round, `duelsTo*` le nombre de duels déjà résolus au premier passage.
Ils sont observés après dépenses avant un éventuel Recovery ultérieur.
`afterRound.*` est une observation en fin de round, renoncements inclus.
Les sessions bloquées ne sont pas imputées aux rounds suivants.

Les dépenses de duel utilisent le montant réellement débité, déjà borné aux PA.
Le compteur de cap compare la courbe brute au cap théorique, indépendamment du
solde disponible. Le taux de contre/défense a tous les duels comme dénominateur ;
renversement/échec et dépenses moyennes ont les enchères effectivement ouvertes.
Le gain Recovery inclut les tentatives refusées ou non réalisées, donc les zéros.
Le dépassement initial concerne l'état immédiatement après Recovery.
Le signal de couverture des dépenses exige au moins dix tentatives dans la session.

Le tirage compte les **nouvelles entrées** en main, pas les cartes conservées.
Le délai de répétition est compté en tirages de session, deux joueurs confondus,
mais une répétition concerne le même joueur. Le ratio par joueur-session est
stocké en points de base ; le ratio global uniques/tirages diminue mécaniquement
avec la taille de campagne et n'est pas une mesure de satisfaction.
Les tags de tirage sont ceux de la variante sélectionnable ; ceux d'une main
sont les tags de base des cartes. Un tirage peut contribuer à plusieurs tags.
Le chili affiché est celui de la variante choisie par la politique, pas un
chili intrinsèque de la carte. Les styles ne changent jamais les permissions.

`hand.size` mesure les cartes détenues ; `hand.playableSize` ajoute la disponibilité
d'une variante et d'une valeur de commit. Cette distinction évite de compter une
main conservée devenue non jouable comme quatre possibilités réelles.
Le pool commun est l'intersection des cartes éligibles pour les deux orientations
de joueurs, avant pondération et avant priorité du cycle unseen/seen/played.
`eligible.*` compte les observations normales joueur/round, sans exception Recovery.
« Jamais éligible » reste limité aux contextes visités. Les cartes jamais tirées
sont listées séparément. Aucune incohérence n'est inférée du seul défaut de tirage.

Les comparaisons avec/sans verrou sont observationnelles : le nombre de nouvelles
cartes et la durée de conservation sont mesurés, mais n'identifient pas un effet
causal sur la diversité. Les histogrammes de tags/cartes rendent l'analyse possible.

## Disponibilité des axes futurs

Ces axes sont des possibilités de calcul, pas des étiquettes attribuées.

| Axes | Observations de simulation / événements | Limite des seuls GameEvent Phase 3 |
|---|---|---|
| AUDACE, PRUDENCE | valeurs au commit, sélection.role | nécessite snapshot privé et contexte volontaire |
| DEPENSE_PA, ECONOMIE_PA | ledger PA par origine, soldes | PA_SPENT ne suffit pas pour toutes les origines |
| NEGOCIATION | AUCTION_STARTED/COMMITTED/RESOLVED, propositions | dénominateur d'opportunités à enrichir |
| TENTATION, PROMESSE | CORRUPTION_PROPOSED, accords | payload sans attribution complète de la promesse |
| REALISATION | ACTION_COMPLETED, état d'exécution | distinguer source normale/Recovery/corruption |
| INVERSION | cible d'enchère et inversion réellement retenue | cible non incluse dans AUCTION_COMMITTED |
| INITIATIVE, RECEPTIVITE | proposant, partenaire, rôles volontaires | certains événements sans player_id |
| VARIETE, SPECIALISATION | fréquences cartes/tags, historique privé | requiert les entrées en main non journalisées |
| ESCALADE, MODERATION | propositions, niveau, accord, baisse | IntensityEngine ne renvoie pas de GameEvent |
| RECOVERY_RISK | gate, source, niveau exceptionnel, actions | STATE_UPDATED porte le gain, pas le contexte complet |
| PROLONGATION | MUTUAL_PA_EXTENSION | montant disponible |
| RENONCEMENT_STRATEGIQUE | STRATEGIC_RENUNCIATION | distinct de tout STOP/refus |
| CHANGEMENT_STYLE | style initial et changements | pas de GameEvent de changement de style |

Conclusion : l'orchestrateur de simulation dispose des observations nécessaires,
mais **les seuls événements Phase 3 ne suffisent pas** à calculer tous ces axes
en production. Une extension explicite du contrat d'événements reste à concevoir
avant les profils finaux, sans modifier les moteurs dans cette phase. Aucun
STOP, refus ou petit pool n'alimente un indicateur comportemental négatif.

## Limites de validité

Cette campagne ne simule pas la psychologie, la durée réelle d'actions, le réseau,
la persistance, une rencontre temporaire ou des accessoires non définis. Les
capacités média sont déclarées disponibles, sans capture ni fichier média.
Les sessions hybrides commencent ensemble et ne changent pas de proximité.
Les profils sont figés et les paramètres d'action ouverts ne sont pas inventés.
Les refresh contextuels ne sont pas sollicités : une carte conservée non jouable
peut bloquer la main, ce qui est rapporté sans mulligan implicite.
Les changements de style restent possibles dans les trois scénarios de style :
les distributions y sont des effets d'un style **initial**, pas une expérience
isolant un style constant. Le test contrôlé compare les mêmes candidats et leurs
poids pour prouver l'invariance des permissions.

Les conclusions statistiques sont conditionnelles à cette matrice et à ces
politiques. Des scénarios plus réalistes et des observations volontaires seront
nécessaires pour un calibrage définitif. La baseline n'est pas remplacée sur la
seule base d'une intention « pression après 8–12 duels » non encore définie par
un seuil unique.

## Analyse de la campagne — MESURE

Campagne principale : **10 000 sessions**, seeds 410000–419999, **462 369 duels**,
27 scénarios de 370 ou 371 sessions chacun, **418,003 s**. Les benchmarks finaux
du même exécutable ont demandé **3,835 s pour 100** et **38,941 s pour 1 000**
sessions. Ces 1 100 exécutions supplémentaires réutilisent les premières seeds ;
elles ne sont pas 1 100 couples indépendants à ajouter aux 10 000 du rapport.
Compilation, chargement catalogue et écriture du JSON sont hors chronométrage.
Les tests et analyses ont tourné pendant une partie de la campagne complète ;
ces durées sont des ordres de grandeur locaux, pas un benchmark matériel isolé.

| Mesure | Première tranche de 1 000 | Campagne de 10 000 |
|---|---:|---:|
| Duels avant 50 % PA A, moyenne conditionnelle | 9,439 | 9,689 |
| Duels avant 50 % PA B, moyenne conditionnelle | 10,139 | 10,377 |
| Contre-enchères / duels | 31,103 % | 31,181 % |
| Recovery / session | 23,516 | 23,231 |
| Mains détenues de quatre cartes | 95,881 % | 95,603 % |

Ces variations modestes sont une vérification descriptive de stabilité, pas
un intervalle de confiance ni une validation de représentativité.

En BALANCED/BALANCED broad (371 sessions), passage à 50 % : moyenne **7,854 / 7,685**
duels, médiane **7 / 7**. Passage à 20 % : moyenne **12,284 / 12,270**, médiane
**12 / 11** (370 et 371 observations). Dans l'ensemble de la matrice, 50 % est
atteint en moyenne après 9,689 / 10,377 duels, mais les asymétries couvrent des
médianes de 2 à 23 : la moyenne globale masque des différences importantes.

La main contient quatre cartes dans **95,603 %** des 946 080 observations,
mais quatre choix avec valeur de commit dans **67,353 %** seulement.
**1 506 sessions** s'arrêtent techniquement faute de sélection jouable ;
8 494 atteignent la limite de 50 rounds. Cette différence inclut les contraintes
de rôle du joueur artificiel, les contextes changés et les petits pools.

Les enchères concernent **31,181 %** des duels et **9,23 %** des dépenses.
Elles vont de **3,78 %** (PA_SAVER/broad) à **68,28 %**
(AUCTION_AGGRESSIVE/asymétrique). Elles ne sont ni globalement systématiques
ni majoritaires dans les dépenses selon les repères déclarés du rapport.
Le résultat initial est renversé dans **74,59 %** des enchères ouvertes.

Recovery : **23,231 tentatives/session**, gain moyen **12,639 PA**, médiane 13.
Aucune des 10 000 sessions ne déclenche le signal « au moins dix tentatives et
gains Recovery couvrant toutes les dépenses ». Le seuil d'entrée à 20 PA et
les actions choisies dans cette campagne donnent un PA après Recovery maximal
de 60 ; cela ne constitue pas un plafond métier et ne remet pas en cause le
droit de dépasser les PA initiaux dans le moteur.

Le niveau actif 5 est observé dans **33,70 %** des sessions, dont les scénarios
de style qui commencent à 5. Les variantes 4/5 représentent **12,219 %** des
tirages avec style initial SOFT, **12,910 %** EPICE, **13,270 %** INTENABLE.
Les pools et les seeds diffèrent entre ces groupes ; les styles peuvent changer.
L'invariance exacte des permissions est vérifiée séparément sur les mêmes profils.

**996 654 tirages**, **100 cartes distinctes**, **2,988 répétitions / 10 tirages**,
concentration top 10 **25,42 %**. Aucune carte ni variante n'est restée
inéligible dans tous les contextes normaux visités, aucune carte n'est restée
non tirée, et les 105 tags ont été rencontrés. Les fréquences utilisent les noms
abrégés du catalogue ; la comparaison aux stable_id accepte le préfixe `tag.`
comme le validateur de Phase 1. Les tableaux distinguent rareté et inéligibilité.

**Zéro violation d'invariant** ; quatre actions finales ignorées après un
changement de contexte, sans exécution devenue impossible. **29 366 transitions**
STOP/refus vérifiées neutres, dont **3 496 STOP**. Ces nombres ne qualifient pas
les comportements des joueurs. Les blocages valides restent des mesures, pas
des erreurs de consentement.

## INTERPRÉTATION

Si « pression significative » signifie 50 % restants, le scénario neutre large
est légèrement plus rapide que la fenêtre 8–12 en moyenne et en médiane.
Si elle signifie l'entrée à 20 %, ses médianes tombent dans la fenêtre et ses
moyennes sont proches de la borne haute. Il serait trompeur de déclarer la cible
atteinte uniquement à partir des moyennes globales de la matrice.

Le maintien de quatre cartes est généralement possible avec un large pool,
mais le nombre de choix effectivement disponibles mérite une étude distincte
avant l'UX. Une réduction automatique de la taille de main ne résoudrait pas
les contraintes de consentement ou les hypothèses de choix du simulateur.
La faible différence entre styles est compatible avec une influence modérée
des poids face au cycle et aux contraintes, sans prouver qu'elle est insuffisante.

Recovery maintient la session active après les premiers seuils ; l'absence de
signal de compensation totale ne démontre pas l'absence de toute stratégie
exploitable. Les scénarios conditionnent les gains aux possibilités du catalogue
et aux réponses artificielles, sans optimisation adversariale de Recovery.

## RECOMMANDATION D'ÉQUILIBRAGE

**Conserver BASELINE ; aucun CANDIDATE_A proposé ni campagne candidate exécutée.**
Le mécanisme de comparaison est testé avec une configuration explicitement
EXPERIMENTAL_TEST_ONLY ; ce test ne constitue pas une recommandation produit.
Les données ne justifient pas encore une modification unique qui améliorerait
simultanément le scénario neutre, les asymétries et les contraintes de variété.

Avant de changer la courbe ou le PA initial : choisir explicitement le seuil de
pression cible, puis comparer des configurations nommées sur les mêmes seeds
et mêmes politiques. Étudier ensuite les choix de rôle et les refresh contextuels
autorisés, puis des expériences appariées de style et verrou constants.
Ces propositions n'élargissent aucun consentement et ne commencent pas la Phase 5.
