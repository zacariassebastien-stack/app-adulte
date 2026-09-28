# Phase 4 — rapport BASELINE

## MESURE

10000 sessions synthétiques ; seeds 410000–419999. 27 scénarios, allocation cyclique. Moteur `dcffdc82e7965122b634c75ef4555178a1289ba7`.

Durée : 418.003 s (exécutable Dart, windows, hors compilation et écriture JSON).

Limites : `{"maxRounds":50,"maxActions":5000,"maxRecoveryCycles":100}`. 462369 duels résolus ; 9165 rounds renoncés. Arrêts techniques : `{"maxRounds":8494,"no_playable_hand":1506}`.

Paramètres, probabilités, profils synthétiques et toutes les distributions : [JSON complet](simulation_baseline.json). Protocole, dénominateurs et limites : [documentation Phase 4](phase4_simulation.md).

### PA

| Joueur | PA initial | PA final moyen / médian | Minimum / maximum observés | Duels avant 50 % (moyenne / médiane ; n) | Avant 20 % | Avant 0 |
|---|---:|---:|---:|---:|---:|---:|
| a | 100.000 | 16.882 / 16.000 | 0 / 110 | 9.689 / 7.000 ; 9704 | 14.222 / 11.000 ; 9390 | 17.314 / 15.000 ; 8149 |
| b | 100.000 | 16.355 / 15.000 | 0 / 119 | 10.377 / 8.000 ; 9698 | 15.313 / 13.000 ; 9310 | 18.505 / 16.000 ; 7991 |

Les seuils sont conditionnels aux joueurs qui les atteignent. Les autres sont censurés, jamais comptés comme zéro. Les moyennes par round ci-dessous ne portent que sur les sessions encore observables.

| Round | PA A moyen / médian | PA B moyen / médian | n A | 🌶️ moyen |
|---:|---:|---:|---:|---:|
| 1 | 91.179 / 96.000 | 93.158 / 98.000 | 9918 | 1.521 |
| 2 | 82.802 / 90.000 | 86.416 / 92.000 | 9918 | 1.592 |
| 3 | 74.490 / 80.000 | 79.682 / 85.000 | 9917 | 1.661 |
| 4 | 66.493 / 72.000 | 72.805 / 78.000 | 9910 | 1.738 |
| 5 | 60.207 / 66.000 | 66.079 / 71.000 | 9898 | 1.811 |
| 6 | 54.511 / 59.000 | 59.937 / 66.000 | 9887 | 1.874 |
| 7 | 49.446 / 52.000 | 54.312 / 59.000 | 9875 | 1.938 |
| 8 | 45.001 / 45.000 | 49.058 / 52.000 | 9870 | 2.002 |
| 9 | 41.057 / 39.000 | 44.561 / 45.000 | 9862 | 2.062 |
| 10 | 37.521 / 34.000 | 40.767 / 40.000 | 9850 | 2.116 |
| 11 | 34.596 / 29.000 | 37.260 / 34.000 | 9830 | 2.166 |
| 12 | 32.084 / 26.000 | 34.395 / 30.000 | 9817 | 2.211 |
| 13 | 29.825 / 24.000 | 31.852 / 27.000 | 9796 | 2.265 |
| 14 | 27.940 / 22.000 | 29.552 / 24.000 | 9783 | 2.306 |
| 15 | 26.503 / 21.000 | 27.766 / 23.000 | 9767 | 2.346 |
| 16 | 25.039 / 20.000 | 26.099 / 22.000 | 9750 | 2.393 |
| 17 | 23.844 / 19.000 | 24.539 / 20.000 | 9733 | 2.438 |
| 18 | 22.899 / 18.000 | 23.347 / 19.000 | 9718 | 2.477 |
| 19 | 22.067 / 17.000 | 22.040 / 18.000 | 9698 | 2.512 |
| 20 | 21.240 / 16.000 | 21.180 / 17.000 | 9672 | 2.545 |
| 21 | 20.553 / 16.000 | 20.505 / 17.000 | 9648 | 2.579 |
| 22 | 19.941 / 16.000 | 19.571 / 16.000 | 9632 | 2.618 |
| 23 | 19.370 / 16.000 | 19.036 / 16.000 | 9604 | 2.651 |
| 24 | 18.838 / 15.000 | 18.525 / 16.000 | 9575 | 2.687 |
| 25 | 18.532 / 15.000 | 17.775 / 15.000 | 9551 | 2.725 |
| 26 | 18.129 / 15.000 | 17.324 / 15.000 | 9524 | 2.762 |
| 27 | 17.839 / 15.000 | 16.953 / 14.000 | 9497 | 2.794 |
| 28 | 17.483 / 15.000 | 16.558 / 14.000 | 9465 | 2.827 |
| 29 | 17.070 / 14.000 | 16.263 / 14.000 | 9442 | 2.858 |
| 30 | 16.797 / 14.000 | 16.002 / 14.000 | 9413 | 2.891 |
| 31 | 16.472 / 14.000 | 15.905 / 14.000 | 9378 | 2.928 |
| 32 | 16.353 / 14.000 | 15.715 / 14.000 | 9338 | 2.959 |
| 33 | 16.323 / 14.000 | 15.338 / 14.000 | 9304 | 2.988 |
| 34 | 16.275 / 14.000 | 15.136 / 14.000 | 9272 | 3.014 |
| 35 | 16.215 / 15.000 | 15.014 / 14.000 | 9239 | 3.043 |
| 36 | 16.018 / 15.000 | 14.822 / 14.000 | 9204 | 3.077 |
| 37 | 15.808 / 14.000 | 14.627 / 14.000 | 9175 | 3.105 |
| 38 | 15.663 / 14.000 | 14.477 / 13.000 | 9136 | 3.135 |
| 39 | 15.466 / 14.000 | 14.356 / 13.000 | 9089 | 3.155 |
| 40 | 15.465 / 14.000 | 14.377 / 13.000 | 9043 | 3.188 |
| 41 | 15.399 / 14.000 | 14.203 / 13.000 | 9001 | 3.214 |
| 42 | 15.178 / 14.000 | 14.072 / 13.000 | 8950 | 3.240 |
| 43 | 15.113 / 14.000 | 14.142 / 13.000 | 8905 | 3.265 |
| 44 | 14.983 / 13.000 | 13.908 / 13.000 | 8859 | 3.292 |
| 45 | 15.015 / 14.000 | 13.844 / 13.000 | 8797 | 3.315 |
| 46 | 14.978 / 14.000 | 13.972 / 13.000 | 8723 | 3.336 |
| 47 | 14.899 / 14.000 | 14.030 / 13.000 | 8662 | 3.361 |
| 48 | 14.849 / 13.000 | 13.838 / 13.000 | 8604 | 3.382 |
| 49 | 14.842 / 14.000 | 13.785 / 13.000 | 8541 | 3.405 |
| 50 | 14.779 / 14.000 | 13.612 / 12.000 | 8494 | 3.423 |

| Dépenses / gains totaux | A | B |
|---|---:|---:|
| duelSpent | 2133363 | 1972229 |
| duelPayments | 189960 | 180913 |
| auctionSpent | 202737 | 226539 |
| chiliSpent | 57950 | 58693 |
| recoveryGain | 1539022 | 1397162 |
| extensionGain | 23850 | 23850 |

Extensions mutuelles : 2385.

### Duels et enchères

Écart moyen / médian : 6.306 / 5.000. Coût moyen / maximal : 8.879 / 25. Cap théorique atteint : 35.75 %. Égalités : 5.54 %. Gagnant à zéro après le duel : 35.63 %.

| Écart | Nombre |
|---:|---:|
| 0 | 25626 |
| 1 | 46951 |
| 2 | 44880 |
| 3 | 41764 |
| 4 | 38497 |
| 5 | 35954 |
| 6 | 33166 |
| 7 | 30233 |
| 8 | 27195 |
| 9 | 24901 |
| 10 | 21607 |
| 11 | 18200 |
| 12 | 16289 |
| 13 | 14266 |
| 14 | 12259 |
| 15 | 10275 |
| 16 | 8271 |
| 17 | 6067 |
| 18 | 4082 |
| 19 | 1886 |

Contre-enchère : 31.18 % des duels. Défense finale : 7.92 % des duels. Renversement : 74.59 % des enchères ; échec de l’initiateur : 25.41 %. PA totaux par enchère, moyenne / médiane : 2.978 / 2.000. Mise maximale : 10. Inversions effectivement retenues : 19983.

Part des enchères dans les dépenses : 9.23 %. Repères descriptifs, sans jugement : quasi inexistante < 5 % des duels ; quasi systématique > 90 % ; majoritaire économiquement > 50 % des dépenses. Comparer les scénarios ci-dessous.

### Recovery

| Mesure | Moyenne | Médiane | Maximum |
|---|---:|---:|---:|
| perSession | 23.231 | 24.000 | 51 |
| firstRound | 11.018 | 10.000 | 48 |
| before | 6.031 | 2.000 | 20 |
| gain | 12.639 | 13.000 | 40 |
| after | 18.670 | 18.000 | 60 |

232310 tentatives, refus 7.95 %, conditions 18.21 %, dépassement PA initiaux 0.00 %. 116254 actions du discard épuisées. 70771 actions principales réalisées au-dessus du niveau actif sur 77918 proposées. 0 sessions avec au moins 10 Recovery et gains Recovery couvrant toutes les dépenses. Ce signal ne prouve pas une boucle exploitable.

### Intensité

Propositions de montée : 52379 ; acceptées et payables : 24155 ; refusées : 20255 ; inabordables : 7969. Coût total : 116643 PA. Baisses mutuellement convenues : 5639 ; remontées gratuites : 3786.

| Niveau | Sessions ayant accédé | Part | Premier round moyen |
|---:|---:|---:|---:|
| 1 | 8893 | 88.93 % | 0.013 |
| 2 | 7877 | 78.77 % | 11.573 |
| 3 | 6230 | 62.30 % | 20.869 |
| 4 | 4787 | 47.87 % | 26.798 |
| 5 | 3370 | 33.70 % | 21.551 |

### Tirage, diversité et main

996654 cartes proposées ; 100 distinctes au niveau campagne. 297766 répétitions dans la même main de joueur au fil de la session, 2.988 par dix tirages. Délai moyen avant répétition : 17.196 tirages des deux joueurs. Concentration top 10 : 25.42 %. Ratio uniques/tirages par joueur-session : 68.121 %.

Pool commun moyen : 33.738 ; pool joueur A / B : 33.803 / 33.806. 66086 observations de pool < 4 ; 2946 à zéro.

| Cartes | Mains détenues | Mains jouables avec une valeur de commit |
|---:|---:|---:|
| 0 | 856 | 2969 |
| 1 | 7328 | 38116 |
| 2 | 13433 | 79914 |
| 3 | 19982 | 187866 |
| 4 | 904481 | 637215 |

Diversité moyenne par main : 4.225 tags, 2.349 précisions, 1.726 niveaux. Répétitions de tags : 0.039. Valeur personnelle moyenne / médiane : 10.993 / 11.000.

`draw.chili` : `{"1":386871,"2":397630,"3":166383,"4":40500,"5":5270}`.

`draw.precision` : `{"OPEN":345050,"GUIDED":372166,"PRECISE":279438}`.

`draw.frequency` : `{"COMMON":789678,"OCCASIONAL":201706,"RARE":5270}`.

`hand.chili` : `{"1":1327153,"2":1326903,"3":515990,"4":124324,"5":16032}`.

Verrous utilisés : 51189 ; conservation moyenne des verrous joués : 8.776 rounds (verrous restants censurés dans le JSON). Renouvellement avec / sans verrou : 0.987 / 1.170 cartes ; 1556 mains verrouillées sans choix jouable. Comparaison observationnelle, pas un effet causal.

### Scénarios

| Scénario | Sessions | Duels | PA A : médiane duels à 50 % | PA B : médiane duels à 50 % | Contre-enchères / duels | Recovery / session | Main complète |
|---|---:|---:|---:|---:|---:|---:|---:|
| BALANCED_vs_BALANCED_broad | 371 | 18192 | 7.000 | 7.000 | 24.39 % | 28.140 | 99.90 % |
| BALANCED_vs_BALANCED_asymmetric | 371 | 16424 | 21.000 | 4.000 | 27.36 % | 20.453 | 87.24 % |
| PA_SAVER_vs_PA_SAVER_broad | 371 | 18100 | 8.000 | 7.000 | 3.78 % | 26.431 | 99.28 % |
| PA_SAVER_vs_PA_SAVER_asymmetric | 371 | 17828 | 23.000 | 5.000 | 4.11 % | 18.251 | 94.71 % |
| PA_SPENDER_vs_PA_SPENDER_broad | 371 | 18162 | 6.000 | 6.000 | 48.41 % | 31.189 | 99.95 % |
| PA_SPENDER_vs_PA_SPENDER_asymmetric | 371 | 18150 | 4.000 | 13.000 | 52.87 % | 25.051 | 99.92 % |
| PA_SAVER_vs_PA_SPENDER_broad | 371 | 18182 | 7.000 | 6.000 | 26.36 % | 28.520 | 99.98 % |
| PA_SAVER_vs_PA_SPENDER_asymmetric | 371 | 13370 | 4.000 | 17.000 | 42.41 % | 16.264 | 73.32 % |
| BOLD_vs_CAUTIOUS_broad | 371 | 18196 | 3.000 | 13.000 | 25.16 % | 27.801 | 99.95 % |
| BOLD_vs_CAUTIOUS_asymmetric | 371 | 13246 | 11.000 | 12.000 | 27.08 % | 12.482 | 73.03 % |
| BOLD_vs_BOLD_broad | 370 | 18121 | 9.000 | 9.000 | 24.63 % | 26.665 | 100.00 % |
| BOLD_vs_BOLD_asymmetric | 370 | 18076 | 20.000 | 6.000 | 27.45 % | 20.632 | 99.98 % |
| VARIETY_SEEKER_vs_SPECIALIST_broad | 370 | 18125 | 7.000 | 7.000 | 24.62 % | 28.405 | 99.82 % |
| VARIETY_SEEKER_vs_SPECIALIST_asymmetric | 370 | 17968 | 4.000 | 18.000 | 26.39 % | 21.878 | 98.71 % |
| AUCTION_AGGRESSIVE_vs_AUCTION_AGGRESSIVE_broad | 370 | 18123 | 6.000 | 6.000 | 59.85 % | 31.697 | 99.70 % |
| AUCTION_AGGRESSIVE_vs_AUCTION_AGGRESSIVE_asymmetric | 370 | 7591 | 3.000 | 13.000 | 68.28 % | 8.557 | 47.40 % |
| AUCTION_AGGRESSIVE_vs_AUCTION_PASSIVE_broad | 370 | 18118 | 7.000 | 7.000 | 31.96 % | 28.600 | 99.94 % |
| AUCTION_AGGRESSIVE_vs_AUCTION_PASSIVE_asymmetric | 370 | 16440 | 15.000 | 4.000 | 54.91 % | 22.624 | 89.12 % |
| CHILI_CLIMBER_vs_CHILI_STABLE_broad | 370 | 18162 | 7.000 | 7.000 | 24.44 % | 28.311 | 99.70 % |
| CHILI_CLIMBER_vs_CHILI_STABLE_asymmetric | 370 | 18118 | 17.000 | 5.000 | 26.62 % | 22.154 | 99.87 % |
| RECOVERY_RISK_vs_BALANCED_broad | 370 | 18079 | 7.000 | 7.000 | 26.58 % | 35.435 | 99.85 % |
| RECOVERY_RISK_vs_BALANCED_asymmetric | 370 | 16313 | 4.000 | 18.000 | 28.21 % | 26.438 | 91.21 % |
| style_SOFT | 370 | 18148 | 12.000 | 12.000 | 26.81 % | 13.954 | 100.00 % |
| style_EPICE | 370 | 18154 | 12.000 | 12.000 | 26.42 % | 13.786 | 100.00 % |
| style_INTENABLE | 370 | 18158 | 12.000 | 12.000 | 26.85 % | 13.816 | 100.00 % |
| similar_tastes | 370 | 18099 | 7.000 | 7.000 | 23.00 % | 28.614 | 99.98 % |
| bold_saver_composed | 370 | 16726 | 2.000 | 23.000 | 59.57 % | 21.081 | 88.06 % |

Styles initiaux : les nombres ci-dessous sont des tirages par niveau de variante. Les détails de précision, fréquence et tags figurent dans chaque scénario JSON.

| Style initial | 🌶️1 | 🌶️2 | 🌶️3 | 🌶️4 | 🌶️5 |
|---|---:|---:|---:|---:|---:|
| SOFT | 5537 | 17725 | 10741 | 4011 | 722 |
| EPICE | 5192 | 17567 | 10971 | 4252 | 748 |
| INTENABLE | 5242 | 17253 | 11100 | 4345 | 795 |

### Catalogue et anomalies

- neverEligibleCards : `[]`.
- neverEligibleVariants : `[]`.
- neverDrawnCards : `[]`.
- unusedTags : `[]`.

« Jamais éligible » signifie dans les contextes normaux effectivement visités, pas une preuve universelle d’incohérence du catalogue. Les refus structurés figurent dans `frequencies.ineligibility`.

Violations d’invariants : 0 ; rounds sans choix jouable : 1506 ; actions revalidées puis ignorées après changement contextuel : 4. Transitions STOP/refus vérifiées neutres : 29366 ; STOP : 3496.

Fréquences par carte (éligibilité = observations joueur/round, tirage = nouvelles entrées en main) :

| Carte | Éligible | Tirée | Part des tirages |
|---|---:|---:|---:|
| card.anal_caress | 258688 | 5987 | 0.60 % |
| card.anal_manual | 175866 | 4196 | 0.42 % |
| card.anal_oral | 113546 | 2616 | 0.26 % |
| card.anal_penetration | 110832 | 2654 | 0.27 % |
| card.anal_play | 237670 | 5448 | 0.55 % |
| card.bath_together | 383900 | 9241 | 0.93 % |
| card.bite | 386146 | 9370 | 0.94 % |
| card.blindfold | 383820 | 9365 | 0.94 % |
| card.body_to_body | 386406 | 9045 | 0.91 % |
| card.caress | 367378 | 15487 | 1.55 % |
| card.chest_play | 382520 | 9096 | 0.91 % |
| card.choose_my_photo | 34160 | 1592 | 0.16 % |
| card.choose_outfit | 497736 | 22732 | 2.28 % |
| card.choose_pose | 413974 | 11954 | 1.20 % |
| card.choose_sex_position | 187198 | 4641 | 0.47 % |
| card.close_eyes | 520492 | 24554 | 2.46 % |
| card.clothed_rubbing | 295410 | 6585 | 0.66 % |
| card.copy_position | 511174 | 23191 | 2.33 % |
| card.dance_for_me | 535468 | 26107 | 2.62 % |
| card.deep_kiss | 238654 | 5940 | 0.60 % |
| card.dominate_me | 260930 | 6940 | 0.70 % |
| card.facesitting | 186052 | 4497 | 0.45 % |
| card.feet_play | 383214 | 9182 | 0.92 % |
| card.flirty_message | 91550 | 9087 | 0.91 % |
| card.full_striptease | 232892 | 5685 | 0.57 % |
| card.genital_rubbing | 277422 | 6575 | 0.66 % |
| card.give_order | 379984 | 10001 | 1.00 % |
| card.guess_touch | 489244 | 19109 | 1.92 % |
| card.hands_bound | 275626 | 6794 | 0.68 % |
| card.hug | 216172 | 9162 | 0.92 % |
| card.i_decide | 378542 | 10064 | 1.01 % |
| card.immobilize | 278468 | 6854 | 0.69 % |
| card.imposed_position | 380708 | 9013 | 0.90 % |
| card.intimate_caress | 231772 | 5558 | 0.56 % |
| card.intimate_massage | 257276 | 6133 | 0.62 % |
| card.intimate_video | 49870 | 2763 | 0.28 % |
| card.kiss_me | 303830 | 14121 | 1.42 % |
| card.lap_sit | 365352 | 12903 | 1.29 % |
| card.let_me_watch | 526624 | 25228 | 2.53 % |
| card.look_at_me | 522084 | 24878 | 2.50 % |
| card.make_wait | 406794 | 11576 | 1.16 % |
| card.manual_intimate | 277044 | 6582 | 0.66 % |
| card.massage | 405984 | 16739 | 1.68 % |
| card.masturbate_partner | 257200 | 5845 | 0.59 % |
| card.masturbate_self_visible | 201154 | 4661 | 0.47 % |
| card.masturbation | 280828 | 7597 | 0.76 % |
| card.mutual_masturbation | 179812 | 4919 | 0.49 % |
| card.neck_kisses | 324080 | 13188 | 1.32 % |
| card.nipple_stimulation | 274740 | 6784 | 0.68 % |
| card.no_touch | 408312 | 11613 | 1.17 % |
| card.nude_photo | 216362 | 5376 | 0.54 % |
| card.nude_video_call | 22752 | 1186 | 0.12 % |
| card.nudity | 281080 | 7366 | 0.74 % |
| card.obey_order | 383136 | 10115 | 1.01 % |
| card.oral_give | 175568 | 4155 | 0.42 % |
| card.oral_receive | 174604 | 4171 | 0.42 % |
| card.pose | 538776 | 26567 | 2.67 % |
| card.private_exhibition | 376872 | 10326 | 1.04 % |
| card.private_runway | 537570 | 26473 | 2.66 % |
| card.private_video_call | 56424 | 3206 | 0.32 % |
| card.private_voyeur | 282348 | 8266 | 0.83 % |
| card.remote_instruction | 55128 | 2904 | 0.29 % |
| card.remove_one_clothing | 429869 | 15976 | 1.60 % |
| card.remove_two_clothing | 329142 | 7739 | 0.78 % |
| card.rp_bar | 530830 | 26542 | 2.66 % |
| card.rp_boss_employee | 283884 | 8087 | 0.81 % |
| card.rp_celebrity_fan | 413324 | 12000 | 1.20 % |
| card.rp_delivery | 412240 | 11859 | 1.19 % |
| card.rp_masseur | 386450 | 9430 | 0.95 % |
| card.rp_master_servant | 283322 | 8148 | 0.82 % |
| card.rp_medical | 273830 | 6513 | 0.65 % |
| card.rp_photographer | 411896 | 11840 | 1.19 % |
| card.rp_royalty_servant | 410978 | 11990 | 1.20 % |
| card.rp_strangers | 533846 | 27047 | 2.71 % |
| card.scratches | 389670 | 9469 | 0.95 % |
| card.sensory_play | 468556 | 16576 | 1.66 % |
| card.sensual_caress | 303534 | 7181 | 0.72 % |
| card.sensual_massage | 347570 | 8424 | 0.85 % |
| card.sexting | 62368 | 3506 | 0.35 % |
| card.shower_together | 385958 | 9478 | 0.95 % |
| card.simulate_69 | 386948 | 8934 | 0.90 % |
| card.simulate_act | 404626 | 11000 | 1.10 % |
| card.simulate_facesitting | 388720 | 9133 | 0.92 % |
| card.simulate_oral | 385796 | 9129 | 0.92 % |
| card.simulate_penetration | 386706 | 9130 | 0.92 % |
| card.sixty_nine | 173300 | 4143 | 0.42 % |
| card.spanking | 273240 | 6656 | 0.67 % |
| card.striptease | 300368 | 7142 | 0.72 % |
| card.submit | 284018 | 7989 | 0.80 % |
| card.suggestive_photo | 305320 | 7524 | 0.75 % |
| card.temperature_play | 384874 | 9455 | 0.95 % |
| card.tie_me | 275028 | 6613 | 0.66 % |
| card.underwear_only | 392064 | 10315 | 1.03 % |
| card.underwear_photo | 302382 | 7619 | 0.76 % |
| card.undress_me | 375620 | 8592 | 0.86 % |
| card.undress_partner | 381554 | 8798 | 0.88 % |
| card.undressing | 439360 | 16869 | 1.69 % |
| card.vaginal_penetration | 177038 | 4252 | 0.43 % |
| card.watch_no_touch | 308224 | 7719 | 0.77 % |
| card.you_decide | 373778 | 9874 | 0.99 % |

Repères descriptifs : carte extrêmement rare < 0,1 % des tirages ; omniprésente > 5 %. Ces seuils ne sont ni des règles ni des objectifs. Les fréquences de tous les tags sont dans le JSON.

Cartes extrêmement rares : `[]`. Cartes omniprésentes : `[]`.

Tags sous-représentés (< 0,1 % des occurrences de tags) : `["media.live.nude","media.video.nude"]`. Tags surreprésentés (> 5 %) : `[]`. Ce sont des seuils descriptifs, sans objectif de fréquence éditoriale.

| Tag (20 plus fréquents) | Présences |
|---|---:|
| staging.position | 36094 |
| sensory.eyes_closed | 35339 |
| clothing.remove | 35186 |
| observation.be_watched | 34718 |
| observation.watch | 32597 |
| contact.body | 31110 |
| roleplay.strangers | 27047 |
| staging.pose | 26567 |
| roleplay.bar_meeting | 26542 |
| staging.runway | 26473 |
| staging.dance | 26107 |
| staging.pose_choice | 23082 |
| clothing.outfit_choice | 22732 |
| media.photo.send | 22111 |
| clothing.nudity | 20278 |
| control.no_touch | 19332 |
| sensory.touch_guess | 19109 |
| clothing.underwear | 17736 |
| clothing.partner_remove | 17390 |
| clothing.undressing | 16869 |

## INTERPRÉTATION

Ces données caractérisent les décisions artificielles documentées, pas les comportements de couples réels. Les différences de scénarios et la censure interdisent de résumer tout l’équilibrage par une moyenne globale. Voir l’analyse explicitement séparée dans [la documentation Phase 4](phase4_simulation.md).

## RECOMMANDATION D’ÉQUILIBRAGE

Aucune modification automatique de BASELINE. La décision concernant un éventuel candidat et les essais complémentaires sont consignés dans [la documentation Phase 4](phase4_simulation.md). Aucun consentement ne doit être élargi pour augmenter la variété.
