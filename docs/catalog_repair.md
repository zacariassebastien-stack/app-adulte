# Correction du catalogue — 27 septembre 2026

Base : `3a0b24a2de2a981d871e05d181fc254b485526ab`.

## Hiérarchie et consentement

Les 93 références parent invalides correspondaient à 30 IDs distincts.
Ces 30 parents sont créés, ainsi que `profile.media`, nécessaire pour relier
photo, vidéo et direct. Les namespaces de premier niveau ont parent_id null ;
chaque niveau inférieur pointe sur son préfixe immédiat. Les 98 éléments
existants sont conservés à l'identique, y compris leurs parents.

Tous les ajouts sont enabled et explicit_acceptance_required=true, avec
GENERAL_ONLY, conformément aux exigences GENERAL du seed. Les parents média
sont MEDIA, les rapports de pouvoir et le contrôle DYNAMIC, le corps BODY_AREA,
le contexte CONTEXT, les jeux de rôle ROLEPLAY et les autres PRACTICE.
Aucun nouveau type de regroupement n'est introduit dans le contrat.

L'exclusion d'un parent doit bloquer les descendants concernés. Son acceptation
ne vaut jamais acceptation d'une feuille. Les exigences existantes sont toutes
conservées et aucune exigence précise n'est remplacée par un parent.

Les quatre définitions V2 manquantes sont ajoutées :
`profile.media.video.suggestive`, `profile.media.video.nude`,
`profile.media.live.instruction` et `profile.power.order`.
Ce dernier est aussi l'un des 30 parents : il n'est pas créé deux fois.
Un élément supplémentaire, `profile.distance.instruction.receive`, permet de
représenter explicitement le consentement de la variante guidée à distance.
Total : 98 + 31 + 3 + 1 = **133 éléments**.

## Tags V2

| Tag ajouté | technical_only | Motif |
|---|---|---|
| tag.duration.long | true | Indication de durée, pas une pratique supplémentaire |
| tag.simulation.guided | true | Précision de présentation ; le consentement à la simulation reste obligatoire |
| tag.distance.instruction.receive | false | Accord pour recevoir une consigne |
| tag.media.video.suggestive | false | Dimension média à accepter explicitement |
| tag.media.video.nude | false | Dimension média à accepter explicitement |
| tag.media.live.instruction | false | Dimension média à accepter explicitement |
| tag.power.order | false | Dynamique à accepter explicitement |

Les 98 définitions existantes sont inchangées. Total : **105 tags**.
Un tag technique ne confère aucune permission et ne supprime aucune exigence.

## Révision des variantes

Quatorze exigences REQUIRED, GENERAL, minimum_status=ACCEPTED sont ajoutées
aux quatorze variantes listées dans
`test/fixtures/catalog_consent_additions.json` : baiser prolongé, caresse et
massage sensuels, deux retraits de vêtements, observation, trois variantes
sensorielles, choix de pose, consigne reçue à distance, choix de pose photo,
variante massage du jeu de rôle et message du jeu de rôle au bar.
Les autres dimensions sensibles V2 disposaient déjà d'exigences explicites,
notamment nudité, vidéo, direct, restriction de mouvement et ordres.

Il s'agit d'une correction éditoriale déclarée, sans inférence à l'exécution
à partir des tags. Le test d'acceptation protège également les exigences de
chaque dimension non technique ajoutée par les variantes du seed.

Le codec peut stocker un prérequis média mais aucun identifiant de capacité
n'est défini. Aucun identifiant ni règle conditionnelle n'est inventé : voir
`open_questions.md` pour les décisions nécessaires avant le moteur.

## Version et provenance

Le schéma reste 1. catalog_version passe de 2 à 3, profile_version de 1 à 2 ;
content_version augmente sur chaque carte dont une variante est corrigée.
Les noms des fichiers restent ceux déclarés par le loader et les assets.
Aucun stable_id existant, texte d'action, niveau, mode ou effet n'est modifié.

`source_hashes.json` reste l'attestation historique de l'archive d'origine,
consultable au commit de base ; il ne décrit pas les trois fichiers corrigés.
`catalog_hashes.json` décrit les trois fichiers actifs après correction.
Les autres fichiers du seed, dont VALIDATION_V2.json, sont des références
historiques ; seul `catalog_audit.json` régénéré par le validateur fait foi.

`test/fixtures/catalog_baseline.json` est une projection du commit de base :
profils et tags d'origine, IDs des actions et paramètres, exigences et enabled.
Elle protège la conservation des identités et l'absence d'assouplissement.
Le validateur de production reste inchangé, strict et sans exception.
