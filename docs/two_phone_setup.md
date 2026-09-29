# Tester le lobby sur deux téléphones Android

Ce guide configure uniquement le lobby à deux appareils. Il ne synchronise pas
encore les cartes ou les duels.

## 1. Créer le projet Supabase

1. Ouvrez <https://supabase.com/dashboard> et créez un compte si nécessaire.
2. Cliquez sur **New project**.
3. Choisissez un nom, un mot de passe de base de données et une région proche.
4. Attendez que le projet soit prêt.

## 2. Activer les utilisateurs anonymes

1. Dans le menu Supabase, ouvrez **Authentication**, puis **Providers**.
2. Ouvrez **Anonymous Sign-Ins**.
3. Activez cette option et enregistrez.

Chaque installation de l'application recevra ainsi sa propre identité. Pour un
test public, Supabase recommande aussi d'activer un CAPTCHA afin de limiter les
abus. Ce n'est pas nécessaire pour un test privé sur deux téléphones.

## 3. Créer les tables et les règles de sécurité

1. Dans Supabase, ouvrez **SQL Editor** puis **New query**.
2. Ouvrez localement le fichier
   `supabase/migrations/202609290001_two_phone_lobby.sql`.
3. Copiez tout son contenu dans l'éditeur SQL Supabase.
4. Cliquez sur **Run** une seule fois.

La migration crée `game_sessions` et `session_players`, leurs fonctions
atomiques de création/join et les politiques RLS. Un utilisateur authentifié ne
peut lire que les sessions dont il est membre. Les écritures passent par les
fonctions contrôlées ; un troisième joueur, un code expiré et les commandes
dupliquées sont refusés ou rendus idempotents. La table `session_players` est
ajoutée à Supabase Realtime.

## 4. Récupérer les deux valeurs client

1. Cliquez sur **Connect** dans le projet Supabase.
2. Copiez **Project URL**.
3. Copiez la **Publishable key**. Sur un ancien projet, elle peut être nommée
   clé `anon` publique.

N'utilisez jamais la clé `service_role`, une secret key ou le mot de passe de la
base dans l'application. Une application mobile ne peut pas garder un secret.

## 5. Préparer Android

1. Activez les options développeur et le débogage USB sur les deux téléphones.
2. Branchez le premier téléphone au PC et acceptez l'autorisation USB.
3. Dans un terminal ouvert à la racine du projet, vérifiez sa présence avec
   `flutter devices`.

## 6. Lancer ou construire l'application

Remplacez les exemples par les deux valeurs copiées :

```powershell
flutter run --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=VOTRE_CLE_PUBLIQUE
```

Pour produire un APK installable sur les deux téléphones :

```powershell
flutter build apk --release --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=VOTRE_CLE_PUBLIQUE
```

L'APK se trouve ensuite dans `build/app/outputs/flutter-apk/app-release.apk`.
Installez le même APK sur les deux téléphones, par USB ou en copiant le fichier.

## 7. Faire le test

1. Ouvrez l'application sur le téléphone A.
2. Appuyez sur **Créer une partie**.
3. Notez le code de six caractères affiché sous « En attente de votre
   partenaire ».
4. Ouvrez l'application sur le téléphone B.
5. Appuyez sur **Rejoindre une partie**, saisissez le code puis **Rejoindre**.
6. Les deux téléphones doivent afficher automatiquement **Partie prête** et
   `2/2 joueurs connectés`.

Si la connexion est perdue, vérifiez Internet puis utilisez **Réessayer**. Un
code reste valable deux heures. Pour recommencer après expiration, créez une
nouvelle partie sur le téléphone A.
