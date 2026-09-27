# Vérification locale — 27 septembre 2026

Environnement : Windows, Flutter 3.47.5 / Dart 3.13.4.

| Vérification | Résultat |
|---|---|
| `dart analyze` | Réussi, aucun problème |
| `flutter analyze` | Réussi, aucun problème (vérification finale) |
| `dart format --output=none --set-exit-if-changed lib test tool` | Réussi |
| `dart test test/domain test/catalog` | 72 tests réussis |
| `flutter test` | 73 tests réussis |
| `flutter build bundle --debug --target-platform android-arm64` | Réussi, kernel et assets produits |
| `flutter build apk --debug` | Échec environnement : Java absent (JAVA_HOME/PATH) |
| `flutter doctor -v` | Android cmdline-tools absent, environnement SDK incomplet |
| Compilation iOS native | Non exécutée : nécessite macOS/Xcode |
| Audit V2 strict | Échec attendu, 104 erreurs de références ; code retour 1 |
| Intégrité des neuf fichiers source | SHA-256 identiques aux entrées de l'archive |

Le bundle Flutter compilé est une vérification du code et des assets ; ce n'est
pas un APK installable. La compilation native Android nécessite un JDK compatible
avec Gradle et le SDK Android complet. Rien n'a été installé globalement.

Le code et les tests de fondation sont vérifiés, mais l'acceptation complète de
la phase 1 reste bloquée sur les données réelles décrites dans open_questions.md.
Le résultat du test de rejet du catalogue n'est pas un certificat de validité.

La CI contient les contrôles de format, analyse, tests, compilation Android,
et un job d'acceptation du catalogue distinct. Aucun résultat CI distant n'est
revendiqué ; ces jobs s'exécuteront au prochain push/PR.
