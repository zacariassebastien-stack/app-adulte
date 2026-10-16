> **Audit historique non appliqué, remplacé par les décisions finales du merge.**
> Le questionnaire V4 et ses associations sont conservés, avec UNSURE = 18.
> Aucune des propositions de traduction ci-dessous ne constitue une instruction active.
> Les exceptions finales sont documentées dans `merge_origin_main_lot6.md` (022, P3, 013).

# Traduction du questionnaire V4 vers les préférences conceptuelles — proposition à valider

**Statut : audit uniquement. Aucune traduction appliquée au questionnaire, au profil ou au calcul. Aucun commit de merge créé.**

Références : Lots 1–6 (`2b1845c44a06cf20316888465e3649a0fb9f4ba4`) pour les préférences conceptuelles validées ; V4 distant (`e35cf6e470b8891cdb3f1de392af59f0375ef0a9`) pour le questionnaire et ses réponses. Les préférences conceptuelles restent la référence, conformément à la dernière décision.

## Périmètre et méthode

Le fichier V4 contient **17 questions, 30 axes et 120 combinaisons axe/réponse**. Les tableaux ci-dessous couvrent les 30 axes et chacune de leurs écritures existantes. Les quatre réponses sont factorisées dans un premier tableau : chaque ligne du second tableau est à lire pour chacune des quatre réponses, sans différence de mapping selon le score.

Tous les `zone_id` des écritures sont `null` et tous les poids déclarés valent `1.0`. Le moteur actuel ne pondère pas la valeur par ce poids : il recopie le PA de la réponse. Seules les écritures PHOTO_MUTUELLE/VIDEO_MUTUELLE déclarent une fusion `MOST_RESTRICTIVE`. Aucun score nouveau n’est proposé.

Une **identité de vocabulaire** signifie que le même identifiant de préférence existe des deux côtés. Cela ne valide pas automatiquement la portée d’une question générale vers toutes les pratiques, ni un changement de rôle : ces points sont signalés séparément. Les informations sans cible restent explicitement recensées ; aucune suppression n’est proposée.

## Réponses : valeur à conserver lorsque le mapping est validé

| Réponse visible | Valeur V4 | Proposition pour une cible validée |
|---|---:|---|
| J’adore (`LOVE`) | 5 | Reprendre 5, avec rôle et portée validés |
| Ça me plaît (`LIKE`) | 12 | Reprendre 12, avec rôle et portée validés |
| Je ne sais pas (`UNSURE`) | 20 | Reprendre 20 ; ne pas inventer une certitude ou une autre valeur |
| Exclu (`EXCLUDED`) | aucune, `excluded=true` | Conserver l’exclusion ; ne pas la convertir en 20 ou en valeur par défaut |

Aucune réponse absente ne devient « autorisée ». Une réponse concernant une pratique précise n’est pas étendue silencieusement à une préférence plus générale.

## Table complète des questions et axes

Les IDs Q01…Q17 abrègent exactement `question.v1.01`…`question.v1.17`. Les préférences conceptuelles sont affichées sans le préfixe `v3.preference.`. `Tag@RÔLE` indique le rôle réellement écrit, après application de `target_role`.

| Question / axe / libellé visible | Écritures V4 actuelles (toutes) | Identités de vocabulaire proposées | Informations sans cible directe ; validation requise |
|---|---|---|---|
| Q01 Câlins — `mutuel` « Ensemble » | calin@MUTUEL; contact_corps@MUTUEL; frotter@MUTUEL | frotter@MUTUEL → frotter@MUTUEL | A1 ; sans cible directe : calin, contact_corps |
| Q02 Baisers — `faire` « Faire » | embrasser@FAIRE | embrasser@FAIRE → embrasser@FAIRE | D1 ; A2 pour LANGUE |
| Q02 Baisers — `recevoir` « Recevoir » | embrasser@RECEVOIR | embrasser@RECEVOIR → embrasser@RECEVOIR | D1 ; A2 pour LANGUE |
| Q03 Jeux de mains — `faire` « Faire » | main@FAIRE | Aucune | A3 ; sans cible directe : main |
| Q03 Jeux de mains — `recevoir` « Recevoir » | main@RECEVOIR | Aucune | A3 ; sans cible directe : main |
| Q04 Jeux de bouche — `faire` « Faire » | bouche@FAIRE | Aucune | A4 ; sans cible directe : bouche |
| Q04 Jeux de bouche — `recevoir` « Recevoir » | bouche@RECEVOIR | Aucune | A4 ; sans cible directe : bouche |
| Q05 Nudité — `moi` « Moi » | nudite@FAIRE; enlever@FAIRE; sous_vetements@FAIRE; striptease@FAIRE; tenue@FAIRE | enlever@FAIRE → enlever@FAIRE; sous_vetements@FAIRE → sous_vetements@FAIRE; tenue@FAIRE → tenue@FAIRE | A5 ; sans cible directe : nudite, striptease |
| Q05 Nudité — `partenaire` « Mon·ma partenaire » | nudite@RECEVOIR; enlever@RECEVOIR; sous_vetements@RECEVOIR; striptease@RECEVOIR; tenue@RECEVOIR | enlever@RECEVOIR → enlever@RECEVOIR; sous_vetements@RECEVOIR → sous_vetements@RECEVOIR; tenue@RECEVOIR → tenue@RECEVOIR | A5 ; sans cible directe : nudite, striptease |
| Q06 Zones intimes — `faire` « Toucher » | jeu_intime@FAIRE; masturbation@FAIRE; doigts@FAIRE; facesitting@FAIRE; ejaculation@FAIRE; pieds@FAIRE | masturbation@FAIRE → masturbation@FAIRE; doigts@FAIRE → doigts@FAIRE; ejaculation@FAIRE → ejaculation@FAIRE | A6 ; sans cible directe : jeu_intime, facesitting, pieds |
| Q06 Zones intimes — `recevoir` « Être touché·e » | jeu_intime@RECEVOIR; masturbation@RECEVOIR; doigts@RECEVOIR; facesitting@RECEVOIR; ejaculation@RECEVOIR; pieds@RECEVOIR | masturbation@RECEVOIR → masturbation@RECEVOIR; doigts@RECEVOIR → doigts@RECEVOIR; ejaculation@RECEVOIR → ejaculation@RECEVOIR | A6 ; sans cible directe : jeu_intime, facesitting, pieds |
| Q07 Sexe oral — `faire` « Faire » | oral@FAIRE | Aucune | A7 ; sans cible directe : oral |
| Q07 Sexe oral — `recevoir` « Recevoir » | oral@RECEVOIR | Aucune | A7 ; sans cible directe : oral |
| Q08 Pénétration — `faire` « Faire » | penetration_vaginale@FAIRE; vaginal@FAIRE | Aucune | A8 ; sans cible directe : penetration_vaginale, vaginal |
| Q08 Pénétration — `recevoir` « Recevoir » | penetration_vaginale@RECEVOIR; vaginal@RECEVOIR | Aucune | A8 ; sans cible directe : penetration_vaginale, vaginal |
| Q09 Pratiques anales — `faire` « Faire » | anal@FAIRE | Aucune | A9 ; sans cible directe : anal |
| Q09 Pratiques anales — `recevoir` « Recevoir » | anal@RECEVOIR | Aucune | A9 ; sans cible directe : anal |
| Q10 Plaisir en solo — `solo` « Moi » | masturbation@SOLO | masturbation@SOLO → masturbation@SOLO | D2 ; A10 |
| Q10 Plaisir en solo — `observer` « Voir mon·ma partenaire » | masturbation@OBSERVER | masturbation@OBSERVER → masturbation@OBSERVER | D2 ; A10 |
| Q11 Jouets / accessoires — `faire` « Sur mon·ma partenaire » | sextoy@FAIRE | sextoy@FAIRE → sextoy@FAIRE | D3 ; A11 |
| Q11 Jouets / accessoires — `recevoir` « Sur moi » | sextoy@RECEVOIR | sextoy@RECEVOIR → sextoy@RECEVOIR | D3 ; A11 |
| Q12 Jeux physiques — `faire` « Faire » | frapper@FAIRE; tirer@FAIRE; maintien_cou@FAIRE; temperature@FAIRE; texture@FAIRE | frapper@FAIRE → frapper@FAIRE; tirer@FAIRE → tirer@FAIRE; maintien_cou@FAIRE → maintien_cou@FAIRE | A12 ; sans cible directe : temperature, texture |
| Q12 Jeux physiques — `recevoir` « Recevoir » | frapper@RECEVOIR; tirer@RECEVOIR; maintien_cou@RECEVOIR; temperature@RECEVOIR; texture@RECEVOIR | frapper@RECEVOIR → frapper@RECEVOIR; tirer@RECEVOIR → tirer@RECEVOIR; maintien_cou@RECEVOIR → maintien_cou@RECEVOIR | A12 ; sans cible directe : temperature, texture |
| Q13 Contrôle / lâcher-prise — `faire` « Prendre le contrôle » | controle@FAIRE; ordres@FAIRE; position@FAIRE; attacher@FAIRE; immobiliser@FAIRE; privation_sensorielle@FAIRE; privation_parole@FAIRE; supplier@FAIRE; degradant@FAIRE | controle@FAIRE → controle@FAIRE; ordres@FAIRE → ordres@FAIRE; attacher@FAIRE → attacher@FAIRE; privation_parole@FAIRE → privation_parole@FAIRE; supplier@FAIRE → supplier@FAIRE | A13 ; sans cible directe : position, immobiliser, privation_sensorielle, degradant |
| Q13 Contrôle / lâcher-prise — `recevoir` « Laisser le contrôle à l’autre » | controle@RECEVOIR; ordres@RECEVOIR; position@RECEVOIR; attacher@RECEVOIR; immobiliser@RECEVOIR; privation_sensorielle@RECEVOIR; privation_parole@RECEVOIR; supplier@RECEVOIR; degradant@RECEVOIR | controle@RECEVOIR → controle@RECEVOIR; ordres@RECEVOIR → ordres@RECEVOIR; attacher@RECEVOIR → attacher@RECEVOIR; privation_parole@RECEVOIR → privation_parole@RECEVOIR; supplier@RECEVOIR → supplier@RECEVOIR | A13 ; sans cible directe : position, immobiliser, privation_sensorielle, degradant |
| Q14 Jeux de rôle / mise en scène — `general` « Général » | jeu_role@MUTUEL; simuler@GENERAL; deguisement@GENERAL; danser@GENERAL; paroles_coquines@GENERAL | jeu_role@MUTUEL → jeu_role@MUTUEL; simuler@GENERAL → simuler@GENERAL; danser@GENERAL → danser@GENERAL; paroles_coquines@GENERAL → paroles_coquines@GENERAL | A14 ; sans cible directe : deguisement |
| Q15 Se montrer / regarder — `montrer` « Me montrer » | etre_regarde@FAIRE; photo@FAIRE; video@FAIRE; photo_mutuelle@MUTUEL [MR]; video_mutuelle@MUTUEL [MR] | etre_regarde@FAIRE → etre_regarde@FAIRE; photo@FAIRE → photo@FAIRE; video@FAIRE → video@FAIRE | A15 ; sans cible directe : photo_mutuelle, video_mutuelle |
| Q15 Se montrer / regarder — `regarder` « Regarder mon·ma partenaire » | regarder@RECEVOIR; photo@RECEVOIR; video@RECEVOIR; contenu_adulte@RECEVOIR; photo_mutuelle@MUTUEL [MR]; video_mutuelle@MUTUEL [MR] | regarder@RECEVOIR → regarder@RECEVOIR; photo@RECEVOIR → photo@RECEVOIR; video@RECEVOIR → video@RECEVOIR; contenu_adulte@RECEVOIR → contenu_adulte@RECEVOIR | A15 ; sans cible directe : photo_mutuelle, video_mutuelle |
| Q16 Surprise / découverte — `general` « Général » | surprise_decouverte@GENERAL; nourriture@GENERAL; boisson@GENERAL | Aucune | A16 ; sans cible directe : surprise_decouverte, nourriture, boisson |
| Q17 Lieux inhabituels / prise de risque — `general` « Général » | lieu_inhabituel@GENERAL; lieu_expose@GENERAL; douche_partagee@GENERAL; bain_partage@GENERAL | lieu_inhabituel@GENERAL → lieu_inhabituel@GENERAL; lieu_expose@GENERAL → lieu_expose@GENERAL | A17 ; sans cible directe : douche_partagee, bain_partage |

`[MR]` : la question 15 écrit les mêmes clés `photo_mutuelle@MUTUEL` et `video_mutuelle@MUTUEL` depuis les deux axes. Actuellement, une exclusion l’emporte ; sinon le PA le plus élevé des deux réponses est retenu (5/12/20). Ce mécanisme existant est identifié, pas automatiquement transféré aux préférences PHOTO/VIDEO/ETRE_REGARDE.

## Correspondances directes proposées

- **D1 — Q02** : `embrasser@FAIRE/RECEVOIR` → `embrasser` avec le même rôle et la même réponse. Couvre la préférence EMBRASSER de 002 et de 003 ; ne fournit pas LANGUE pour 003.

- **D2 — Q10, axe solo** : `masturbation@SOLO` reste une préférence de masturbation sur soi. La sémantique est directe ; la normalisation technique éventuelle SOLO/SOI est à valider dans A10. L’axe OBSERVER reste distinct.

- **D3 — Q11** : `sextoy@FAIRE/RECEVOIR` → `sextoy` avec le même rôle et la même réponse. Cette correspondance n’autorise aucun accessoire concret et ne débloque pas 049–052.

Les autres identifiants identiques figurent intégralement dans la colonne « Identités de vocabulaire ». Leur transfert peut être mécanique après validation de la portée de la question et des rôles ci-dessous ; il ne nécessite aucun renommage de préférence.

## Cas ambigus : proposition et décision attendue

| Cas | Écart constaté | Proposition soumise, non appliquée | Décision nécessaire / conséquence |
|---|---|---|---|
| **A1 — Q01 / 001 et 030** | `calin` + `contact_corps` ne sont pas `proximite_physique`. `frotter` existe, mais une réponse « Câlins » ne décrit pas nécessairement 031 Frottement génital. `proximite_physique` est aussi utilisée par 030 Facesitting. | Étudier une traduction de la réponse de Q01 vers PROXIMITE_PHYSIQUE, en conservant les trois informations V4 d’origine. | Valider ou refuser cette portée élargie et son rôle MUTUEL. Ne pas transformer automatiquement l’acceptation de câlins en autorisation de Facesitting ou de frottement génital. |
| **A2 — Q02 / 003** | 003 demande EMBRASSER + LANGUE ; Q02 ne distingue pas la langue. | Conserver EMBRASSER par identité ; laisser LANGUE non renseignée tant que sa source n’est pas validée. | Une réponse aux baisers couvre-t-elle aussi LANGUE ? Aucun oui implicite. |
| **A3 — Q03 / 005** | V4 écrit `main`, alors que 005 Jeu de main demande CARESSER. | Candidat : `main@FAIRE/RECEVOIR` → CARESSER avec le même rôle. Conserver `main` comme donnée source. | Valider l’équivalence « jeu de mains / caresser », qui est partielle sans précision de la question. |
| **A4 — Q04 / 004** | V4 écrit `bouche`. Le contrat de 004 distingue LECHER et SUCER ; ni l’une ni l’autre ne possède une réponse dédiée. | Candidat : reprendre la réponse de Q04 pour les deux techniques, séparément et avec le même rôle. | Valider explicitement si une réponse générale couvre les deux techniques ; sinon elles restent non renseignées. Ne pas ajouter ORAL, PENETRER, ANAL ou VAGINAL automatiquement. |
| **A5 — Q05 / vêtements, dont 013** | V4 écrit nudité, enlever, sous-vêtements, striptease et tenue depuis une seule réponse. ENLEVER, SOUS_VETEMENTS et TENUE existent ; NUDITE/STRIPTEASE n’ont pas de préférence conceptuelle homonyme. 010 demande aussi DANSER/ETRE_REGARDE. 013 est SOI, pas FAIRE/RECEVOIR. | Préserver les trois identités, sans traduire NUDITE en ENLEVER ni STRIPTEASE en DANSER/ETRE_REGARDE. | Valider la portée des réponses « moi / partenaire », et la source SOI de TENUE pour 013. Ne pas recréer de préférences NUDITE ou STRIPTEASE. |
| **A6 — Q06 / intimité** | Une réponse « Toucher / Être touché·e » écrit MASTURBATION, DOIGTS et EJACULATION, plus `jeu_intime`, `facesitting` et `pieds`. Ces derniers ne sont pas des préférences conceptuelles autonomes. | Préserver les trois identités, mais identifier leur origine commune. Ne pas traduire automatiquement FACESITTING → PROXIMITE_PHYSIQUE ni PIEDS → MASTURBATION. | Valider la reprise de cette réponse générale pour les trois pratiques distinctes. 024 emprunte les préférences d’une pratique choisie ; 065 utilise MASTURBATION, avec PIEDS sémantique sans PA propre. |
| **A7 — Q07 / 025, 026, 028** | `oral` ne précise pas LECHER/SUCER ni la zone. 025/026/028 demandent LECHER ; 028 porte une zone anale. | Candidat partiel : ORAL → LECHER dans une portée à définir. Conserver ORAL et sa provenance. | Valider si cette réponse peut renseigner LECHER et pour quelles zones ; ne pas extrapoler automatiquement à l’oral anal ou à 004. |
| **A8 — Q08 / 022, 027** | V4 écrit `penetration_vaginale` et `vaginal`. Le contrat demande PENETRER ; pour 022, aussi DOIGTS et une zone VAGINAL. | Candidat : réponse de Q08 → PENETRER **dans le contexte vaginal seulement**, sans PA propre pour la zone. | Valider si elle couvre la pénétration digitale de 022, la pénétration de 027, ou les deux. Ne pas étendre une réponse vaginale à l’anal ; ne pas perdre la portée VAGINAL lors de la traduction vers une préférence plus générale. |
| **A9 — Q09 / anal** | V4 écrit une préférence `anal`, tandis que le nouveau contrat traite ANAL comme une zone et distingue les techniques. | Conserver la réponse comme information de zone existante ; aucun mapping automatique vers PENETRER, DOIGTS ou LECHER. | Valider le devenir de l’exclusion de zone et de l’ancien PA : une information de zone ne devient pas un PA de technique. |
| **A10 — Q10 / SOLO et OBSERVER** | Les deux axes écrivent MASTURBATION mais décrivent des participations distinctes. Le runtime réduit actuellement plusieurs rôles vers une valeur générale. | Conserver les deux réponses séparées. Candidat technique : SOLO → SOI uniquement pour une pratique sur soi. | Valider cette normalisation ; ne jamais utiliser OBSERVER comme FAIRE, RECEVOIR ou SOI par simple fallback. Ne pas effacer la réponse OBSERVER. |
| **A11 — Q11 / 049–052** | Q11 ne renseigne pas SEXTOY sur SOI, PENETRER, VIBRANT ou CONTROLE_DISTANCE, ni les tags d’un accessoire concret. | Ne reprendre que les deux identités SEXTOY déjà renseignées. | Aucune autre valeur déduite. 049–052 restent indisponibles ; pas de fallback matériel ni de valeur d’accessoire par défaut ajoutée par cette traduction. |
| **A12 — Q12 / jeux physiques** | Une même réponse écrit FRAPPER, TIRER et MAINTIEN_COU, plus TEMPERATURE/TEXTURE sans cible conceptuelle active. | Préserver les trois identités et les deux informations sans cible. | Valider la portée commune des réponses ; ne pas assimiler température/texture à FRAPPER, TIRER ou MAINTIEN_COU. Les réserves de catalogue ne sont pas réactivées. |
| **A13 — Q13 / contrôle** | CONTROLE, ORDRES, ATTACHER, PRIVATION_PAROLE et SUPPLIER ont une identité directe. POSITION/IMMOBILISER n’en ont pas. PRIVATION_SENSORIELLE est plus large que YEUX_BANDES ou PRIVATION_AUDITIVE ; DEGRADANT est plus large que PAROLES_DEGRADANTES. | Conserver les cinq identités. Candidats partiels à examiner : PRIVATION_SENSORIELLE → visuelle/auditive ; DEGRADANT → paroles dégradantes. | Valider ou refuser chaque extension. Ne pas fusionner POSITION/IMMOBILISER dans CONTROLE/ATTACHER sans accord et ne pas autoriser les deux privations à partir d’un oui général. |
| **A14 — Q14 / mise en scène** | V4 écrit JEU_ROLE en MUTUEL ; SIMULER, DANSER et PAROLES_COQUINES en GENERAL ; DEGUISEMENT n’a pas de cible active. | Préserver ces quatre identités avec leurs rôles explicites, et conserver DEGUISEMENT sans cible. | Valider les éventuels changements de rôle nécessaires aux concepts. Ne pas dériver TENUE de DEGUISEMENT ; ne pas dériver ENVOYER de PAROLES_COQUINES. |
| **A15 — Q15 / photo, vidéo et participation mutuelle** | ETRE_REGARDE/PHOTO/VIDEO/REGARDER/CONTENU_ADULTE existent mais les axes « montrer / regarder » sont distincts. PHOTO_MUTUELLE/VIDEO_MUTUELLE sont des agrégats V4, pas des préférences conceptuelles. P3 exige PHOTO/VIDEO + ETRE_REGARDE pour les participants représentés. | Préserver les cinq identités et les deux agrégats d’origine, avec les deux réponses et la règle MR. | Valider comment obtenir les rôles nécessaires au média mutuel sans confondre regarder et être représenté. Ne pas convertir MR en nouvelle valeur pour PHOTO/VIDEO/ETRE_REGARDE sans décision. Q15 ne fournit pas ENVOYER. |
| **A16 — Q16 / surprise** | SURPRISE_DECOUVERTE, NOURRITURE et BOISSON n’ont aucune cible de préférence parmi les concepts actifs. | Aucune traduction proposée ; conserver ces réponses comme informations V4 sans consommateur conceptuel identifié. | Confirmer leur conservation transitoire ; ne pas réintroduire les concepts supprimés/réservés pour leur créer une cible. |
| **A17 — Q17 / lieux** | LIEU_INHABITUEL et LIEU_EXPOSE ont une identité directe. DOUCHE_PARTAGEE/BAIN_PARTAGE n’ont pas de cible active. | Préserver les deux identités et garder les deux informations restantes sans traduction. | Valider la portée du risque partagé par la question ; ne pas assimiler automatiquement douche/bain à un lieu exposé ou inhabituel. |

## Préférences conceptuelles non renseignées sous leur identifiant actuel

| Préférence | Source candidate identifiée | Statut |
|---|---|---|
| PROXIMITE_PHYSIQUE | Q01 ; éventuellement FACESITTING de Q06, qui n’est pas équivalent | A1/A6 |
| LANGUE | Q02 « Baisers » | A2 ; non distinguée |
| CARESSER | Q03 « Jeux de mains » | A3 |
| LECHER | Q04 « Jeux de bouche » et Q07 « Sexe oral » | A4/A7 ; risque de collision et de différence de portée |
| SUCER | Q04 « Jeux de bouche » ; Q07 ne le distingue pas non plus | A4/A7 |
| PENETRER | Q08 vaginal ; Q09 anal ne décrit pas la technique | A8/A9 |
| YEUX_BANDES | Q13 PRIVATION_SENSORIELLE | A13 |
| PRIVATION_AUDITIVE | Q13 PRIVATION_SENSORIELLE | A13 |
| PAROLES_DEGRADANTES | Q13 DEGRADANT | A13 |
| ENVOYER | Aucune question ne demande l’accord pour envoyer un message/média | Aucune équivalence certaine ; ne pas déduire de Q14/Q15 |
| CONTROLE_DISTANCE | Aucune question ne distingue le contrôle à distance | Aucune équivalence certaine ; 052 bloqué |
| VIBRANT | Aucune question ne distingue cet accessoire/caractère | Aucune équivalence certaine ; 052 bloqué |

## Informations V4 sans préférence conceptuelle homonyme

`anal`, `bain_partage`, `boisson`, `bouche`, `calin`, `contact_corps`, `degradant`, `deguisement`, `douche_partagee`, `facesitting`, `immobiliser`, `jeu_intime`, `main`, `nourriture`, `nudite`, `oral`, `penetration_vaginale`, `photo_mutuelle`, `pieds`, `position`, `privation_sensorielle`, `striptease`, `surprise_decouverte`, `temperature`, `texture`, `vaginal`, `video_mutuelle`.

Ces informations restent recensées. ANAL, VAGINAL et PIEDS peuvent porter une sémantique de zone ; cela ne les transforme pas en préférences PA et ne définit pas à lui seul leur traduction. PHOTO_MUTUELLE/VIDEO_MUTUELLE ont une règle d’agrégation à conserver pour audit. Aucune suppression n’est autorisée par ce document.

## Frontières à préserver lors d’une future application

- Conserver les réponses brutes par question/axe ou leur provenance équivalente lorsque plusieurs préférences sont agrégées ; ne pas écraser une réponse par une autre sans règle validée.
- Conserver séparément les rôles et les exclusions. Les rôles MUTUEL/GENERAL/SOLO/SOI/OBSERVER ne sont pas interchangeables par défaut.
- Si deux questions sont finalement traduites vers une même clé, une règle de collision devra être validée ; MR de Q15 n’est pas une autorisation générale de fusionner toutes les réponses.
- Les préférences manuelles, déjà apprises ou propres aux accessoires ne sont pas des réponses au questionnaire : elles ne sont ni écrasées ni recalculées par cet audit.
- Les usages engagés et leurs valeurs historiques restent immuables. Aucun mapping futur ne doit réinterpréter leurs snapshots.
- Aucun changement des piments, stades, zones, capacités ou règles P1–P6. Aucun déblocage des sextoys, aucune nouvelle question, aucune préférence nouvelle et aucune valeur permissive de secours.

## Contrôle de complétude documentaire

17 questions ; 30 axes ; 120 combinaisons réponse/axe ; 94 écritures source ; 55 identifiants V4 distincts. Chaque écriture apparaît dans la table, y compris les quatre écritures d’agrégats mutuels et les substitutions de rôle de Q14/Q15. Ce contrôle valide l’inventaire, pas une traduction métier encore à approuver.

La réconciliation Git reste en cours. La création du commit de merge attend la validation des correspondances et leur raccordement ciblé. Aucun push ni déploiement Supabase.
