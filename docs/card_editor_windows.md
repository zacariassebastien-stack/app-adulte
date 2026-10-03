# ENCHAIRE Card Editor pour Windows

Le projet autonome se trouve dans `tools/card_editor`. Il ouvre directement
l’éditeur existant et réutilise le renderer, les modèles, le catalogue et les
assets du package principal. Il ne démarre ni lobby, ni gameplay, ni Supabase.

Depuis `tools/card_editor`, construire l’application avec :

```powershell
flutter build windows
```

L’exécutable est produit dans :

```text
tools/card_editor/build/windows/x64/runner/Release/ENCHAIRE Card Editor.exe
```

L’outil détecte le dépôt en remontant depuis son dossier de lancement et depuis
le dossier de l’exécutable. Pour choisir explicitement un dépôt :

```powershell
& '.\ENCHAIRE Card Editor.exe' --project-root='C:\chemin\vers\app-adulte'
```

Une sauvegarde écrit quatre fichiers dans
`assets/card_themes/<theme_id>/` : `theme.json`, `layout.json`, `skin.json` et
`illustrations.json`. Elle met aussi à jour `assets/card_themes/index.json` et
enregistre le dossier du thème dans les assets du `pubspec.yaml`. L’application
mobile charge cet index : les changements sont donc disponibles après un
nouveau build mobile.

Les références d’illustrations utilisent les mêmes chemins que l’application.
Une image absente affiche le placeholder standard du `CardRenderer`.

Le sélecteur de direction de preview couvre trois cas : FAIRE (`1 PA`, inverse
RECEVOIR à `20 PA`), RECEVOIR (`20 PA`, inverse FAIRE à `1 PA`) et MUTUEL
(`8 PA` sans valeur inverse). Il permet de vérifier le contraste de la valeur
principale, la ligne secondaire et les valeurs extrêmes sans réintégrer
l'éditeur dans l'application mobile.

`enchaire_signature_v1` apparaît en premier et constitue la référence
canonique. Il peut être modifié et sauvegardé directement par cet outil ;
`classic_v1` reste protégé. Pour une déclinaison, dupliquer le pack Signature
afin de conserver l'original et d'obtenir de nouveaux IDs.

Le panneau de propriétés expose le fond et son dégradé, la matière, les deux
bordures et leur écart, les rayons, le glow, les panneaux, les ombres, les
couleurs de texte, les polices, les tailles et les espacements. Les contrôles
de bloc conservent la responsabilité du layout : position, taille, marge,
padding, rotation, visibilité et ordre visuel.
