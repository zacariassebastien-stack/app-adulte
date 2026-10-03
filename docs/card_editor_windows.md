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
