# Régions corporelles — 002, 004 et 005

Le catalogue actif version 2 définit Embrasser, Jeu de bouche et Jeu de main
comme trois concepts évolutifs. Chacun possède exactement deux stades :

| Stade | Piment | Intention |
| --- | --- | --- |
| 1 | 2 | Sensuelle, douce et exploratoire |
| 2 | 3 | Liberté accrue ; une dimension sexuelle est possible, jamais imposée |

Chaque stade propose Haut du corps (`upper_body`, au-dessus de la ceinture),
Bas du corps (`lower_body`, sous la ceinture, zones intimes comprises), et Libre
(`free`, choix libre dans les limites applicables). Le piment dépend uniquement
du stade, jamais de la région. Aucun modificateur anatomique ni rabais de classe
« zone libre » ne s'applique à ces trois concepts.

## Identités, tirage et profil

Les deux stades éditoriaux sont combinés aux trois régions pour produire six
définitions d'action, par exemple `002.stage.2.region.lower_body`. La clé de note
reste `profil|concept|action|rôle`, avec FAIRE et RECEVOIR indépendants :
**12 présentations par concept, 36 pour les trois**, sans note globale ajoutée.
Le catalogue complet expose 220 présentations. Les anciennes variantes
`002.zone.*`, `004.zone.*` et `005.zone.*` ne sont plus des choix actifs.

Le tirage conserve une seule candidate par concept et deux utilisations par
cycle, correspondant aux deux stades éditoriaux, et non six ou douze. L'action
précise est matérialisée dans la main puis figée à l'engagement. Les signaux
d'apprentissage suivent cette identité et son rôle ; leurs identifiants de
déduplication, confirmations de référence officielle et coefficients restent
ceux du moteur existant.

## Anciennes appréciations et limites

Les anciennes notes restent stockées mais ne sont ni moyennées, ni recopiées,
ni proposées comme appréciations actives. Les nouvelles présentations partent
du profil général/questionnaire (`embrasser`, `bouche`, `main`, selon le rôle).
Les anciennes preuves précises de préférence ne sont pas réutilisées pour
amorcer leur pondération de découverte. Une ancienne autorisation précise ne
devient pas une autorisation régionale.

Décision utilisateur : les exclusions anatomiques précises deviennent des
**limites ciblées d'exécution**, sans interdire toute la région. Une ancienne
exclusion Poitrine / RECEVOIR reste ainsi visible pour cette personne sur Haut
et Libre / RECEVOIR, sans exclure le ventre, le Bas ou FAIRE. Les veto précis et
les préférences anatomiques ou de pratique à portée anatomique sont conservés.
Apprécier une nouvelle présentation ne supprime pas ces limites.

Le profil, les détails de la main et la résolution rappellent localement les
limites personnelles pertinentes. Les textes partagés demandent de vérifier
ensemble les zones et les gestes avant de commencer. Les noms de ces limites
privées ne sont pas ajoutés aux snapshots réseau. Leur respect pendant le geste
repose sur cet échange et le consentement des joueurs : aucune ancienne zone
n'est tirée, suivie ou évaluée en sous-variante cachée.

Les veto de pratique entière, de concept entier et les nouvelles exclusions
précises restent bloquants selon les règles existantes, pour le rôle concerné.
Une région ne vaut jamais autorisation de toutes les pratiques possibles.
Aucun contrôle pénis/vulve n'est nécessaire pour ces cartes génériques ; les
contrôles des pratiques anatomiques explicites restent inchangés ailleurs.

## Usages sauvegardés

Les snapshots engagés, y compris ceux portant une ancienne identité anatomique,
restent lus avec leurs textes, rôles, paramètres, PA et piments figés. Ils ne
sont pas recalculés depuis le catalogue courant. Une ancienne carte non engagée
est rematérialisée parmi les présentations actuelles ; les actions anatomiques
retirées ne sont pas proposées comme nouveaux rejouements.

La taxonomie anatomique historique et le support des anciens concepts `zones`
restent disponibles pour les données et mécanismes qui les utilisent encore.
Le format des clés précises et celui des snapshots réseau sont conservés :
**aucune migration SQL Supabase n'est nécessaire pour ce chantier**.
