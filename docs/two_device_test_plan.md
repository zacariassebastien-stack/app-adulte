# Test ENCHAIRE à deux appareils

Préparer deux appareils avec la même APK et deux comptes distincts. Appliquer
au préalable les migrations Supabase indiquées dans le rapport de livraison.
Pour chaque KO, noter l’appareil, l’heure, le numéro du tour et la phase affichée.

| Étape | Action | Résultat attendu | OK / KO | Notes |
|---|---|---|---|---|
| A. Démarrage | Lancer l’application sur A et B. | Accueil affiché sans erreur ni ancienne session parasite. | ☐ OK ☐ KO | |
| B. Création | Sur A, créer une partie à deux téléphones. | Un code de partie est affiché et A attend B. | ☐ OK ☐ KO | |
| C. Connexion B | Sur B, saisir le code. | Les deux appareils affichent une partie prête avec deux joueurs. | ☐ OK ☐ KO | |
| D. Distribution | Ouvrir le jeu sur A et B. | Chaque joueur reçoit quatre cartes privées ; aucune main adverse n’est visible. | ☐ OK ☐ KO | |
| E. Engagement | Choisir une carte sur chaque appareil, verrouiller une autre carte puis valider. | Le choix est engagé une fois ; le verrou reste local et persistant. | ☐ OK ☐ KO | |
| F. Reveal | Valider d’abord sur A, puis sur B. | Rien n’est révélé avant le second engagement ; les deux choix apparaissent ensuite. | ☐ OK ☐ KO | |
| G. FAIRE / RECEVOIR | Jouer une occurrence dirigée. | La direction et le PA actif affichés correspondent à l’occurrence sur les deux appareils. | ☐ OK ☐ KO | |
| H. MUTUEL | Jouer une occurrence MUTUELLE. | Une valeur unique est utilisée et aucune direction inverse n’est proposée. | ☐ OK ☐ KO | |
| I. Inversion ABA | B propose une inversion, A répond, B adapte une fois, A valide. | Seule l’occurrence initiale change de direction ; aucune boucle ABAB n’est possible. | ☐ OK ☐ KO | |
| J. Enchère ABA | Refaire ABA avec PA et carte(s) d’enchère. | Débit unique, cartes uniques dans le compromis et résultat identique sur A/B. | ☐ OK ☐ KO | |
| K. Recovery | Avec un joueur à 10 PA ou moins, proposer puis accepter une Recovery. | Proposition à gain masqué ; gain appliqué une fois après réalisation ; sortie volontaire possible. | ☐ OK ☐ KO | |
| L. Tour suivant | Terminer l’action puis rendre A et B prêts. | Cartes jouées défaussées, main complétée et nouveau tour unique. | ☐ OK ☐ KO | |
| M. Paramètres | Ouvrir puis fermer les paramètres ; consulter historique et profil privé. | Panneau stable, données privées locales, aucune modification du tour. | ☐ OK ☐ KO | |
| N. Annulation sûre | A valide seul puis annule avant le reveal et choisit une autre carte. | La première occurrence revient en main ; aucun PA ni apprentissage n’est appliqué. | ☐ OK ☐ KO | |
| O. Quitter | Depuis les paramètres, confirmer « Quitter la partie ». | Session fermée sur A et B, retour à l’accueil sans round suivant. | ☐ OK ☐ KO | |
| P. Reconnexion | Pendant commit, ABA, Recovery et attente du tour suivant, fermer puis relancer un appareil. | Phase, main, verrou, PA, occurrence et direction reprennent sans double effet. | ☐ OK ☐ KO | |
| Q. Confidentialité | Comparer les écrans avant reveal et lors d’un refus/exclusion. | Aucune carte exclue, préférence refusée, valeur privée, nonce, main ou verrou adverse n’est visible ; aucun coût/pénalité/statistique négative. | ☐ OK ☐ KO | |
