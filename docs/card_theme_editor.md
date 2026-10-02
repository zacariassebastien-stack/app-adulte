# Card Theme Editor

L’éditeur est un outil interne disponible uniquement en build debug. Depuis le lobby **Jouer à deux**, utiliser l’icône palette dans la barre supérieure. Il n’apparaît pas dans une build release.

L’écran permet de choisir une carte, un thème, le recto ou le verso et trois modes de preview : carte unique, échantillon représentatif et catalogue complet virtualisé. L’échantillon inclut des titres courts et longs, des textes longs, les niveaux 1 et 5 et plusieurs directions.

En mode carte unique :

- toucher un bloc pour le sélectionner ;
- le glisser pour le déplacer ;
- utiliser la poignée bleue pour le redimensionner ;
- régler rotation, alignement, marge, padding et visibilité dans le panneau ;
- modifier couleurs, bordure, rayon, ombre et glow du skin ;
- lire immédiatement les erreurs du validateur.

Les ressources `classic_v1` sont protégées. Il faut les dupliquer avant modification. Les boutons permettent de dupliquer un layout, un skin ou un pack ; chaque duplication reçoit de nouveaux IDs. Les brouillons sont sauvegardés localement avec `SharedPreferences`.

## Créer un nouveau thème sans coder

1. Ouvrir **Card Theme Editor** depuis le menu debug.
2. Sélectionner `classic_v1`, puis utiliser **Dupliquer layout**, **Dupliquer skin** ou **Dupliquer pack**.
3. Déplacer et redimensionner les blocs sur la preview.
4. Modifier les propriétés du skin dans le panneau de droite.
5. Associer les références d’illustrations dans le manifeste si un style illustré existe ; le style par défaut reste le fallback.
6. Contrôler la preview représentative, puis **Preview catalogue**.
7. Sauvegarder et utiliser **Exporter le thème** pour copier le manifeste versionné.
8. Ajouter le manifeste et ses assets validés au pack distribué, puis activer son ID dans la future sélection de thème.

## Validation

Le validateur signale notamment les blocs hors carte, tailles nulles, IDs dupliqués, liens de layout/skin absents, version incompatible, focus d’image invalide et titre masqué. Le catalogue n’est jamais modifié par l’éditeur.
