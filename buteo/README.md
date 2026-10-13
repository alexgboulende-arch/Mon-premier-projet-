# Buteo — Pronostics sportifs

Application mobile de pronostics sportifs inspirée de *Multi Betting Tips*, en
version améliorée. **Statut : application Flutter, étape 1 sur 5 (écrans et données de démonstration).**

## Décisions prises

- Vrai business, Android d'abord, en français, pour le monde francophone.
- Pronostics produits par une **IA**, publiés à **00:00**, avec un indice de confiance.
- Résultats mis à jour automatiquement, historique complet (gagnés et perdus).
- Revenus : coupon VIP à l'unité (500 FCFA), publicité dans la version gratuite,
  abonnements Pro (2 900 FCFA/mois) et Élite (6 900 FCFA/mois), aussi en 3 et 6 mois.
- Rubriques VIP : Score exact, Mi-temps / Fin, Combiné cote 5+, Combiné cote 10+,
  Simples VIP, Live. Le combiné cote 50+ de l'original est abandonné (trop rarement gagnant).
- Pas de liens vers les bookmakers.
- Paiement : Google Play dans l'app ; Mobile Money et crypto aussi (voir « Paiements »).
- Connexion par Google et par numéro de téléphone.
- En plus : équipes favorites, partage d'un prono sur WhatsApp, concours entre
  utilisateurs (sans gain d'argent), journal de paris. Pas d'essai gratuit ni de parrainage.

## Application (`app/`)

Application Flutter pour Android. Chaque envoi de code sur GitHub lance la
construction automatique de l'APK (`.github/workflows/buteo-android.yml`) :
analyse du code, tests, puis publication dans **Releases → « Buteo – version de test »**.

**Installer sur ton téléphone :** ouvre la page *Releases* du dépôt sur le
téléphone, télécharge `buteo-test.apk`, ouvre-le et autorise l'installation.
Les versions suivantes s'installent par-dessus.

Organisation du code :

| Dossier | Contenu |
|---|---|
| `lib/data/` | Rubriques, offres, pronos de démonstration, statistiques |
| `lib/state/` | Formule, coupons, thème et notifications de l'utilisateur |
| `lib/theme/` | Couleurs et polices de la marque |
| `lib/ui/screens/` | Accueil, rubrique, live, stats, offres, profil, démarrage |
| `lib/ui/widgets/` | Carte de prono, tuiles, badges, fenêtres d'achat |
| `test/` | Tests automatiques (générateur, états des matchs, écrans) |

Commandes utiles (dans `app/`) : `flutter test`, `flutter analyze`,
`flutter build apk --release`, `dart run flutter_launcher_icons` (icône).

## Feuille de route

1. **Écrans et données de démonstration** (fait) : toute la maquette en Flutter,
   APK de test construit par GitHub.
2. **Comptes et notifications** : Firebase, connexion Google et téléphone,
   notifications à 00:00, équipes favorites.
3. **Moteur de l'IA** : source de données sportives, calcul des probabilités,
   publication automatique à 00:00, résultats en direct.
4. **Paiements et publicité** : Google Play Billing, Mobile Money et crypto
   sur le site web, AdMob dans la version gratuite.
5. **Communauté et publication** : concours, journal de paris, back-office,
   test fermé puis mise en ligne sur le Play Store.

## Paiements

Google Play impose son propre système de paiement pour les abonnements et les
achats numériques vendus **dans** une app installée depuis le Play Store. Ailleurs
qu'aux États-Unis, au Royaume-Uni, dans l'Espace économique européen et dans
quelques autres pays, l'ouverture aux paiements externes est annoncée au plus
tard pour septembre 2027.

Plan retenu :
- **Dans l'app** : Google Play Billing (abonnements Pro et Élite, coupons).
- **Sur le site web de Buteo** : Mobile Money (via un agrégateur comme
  CinetPay ou FedaPay) et crypto. L'achat est rattaché au compte, et l'app
  débloque l'accès automatiquement à la connexion.
- Dès que Google l'autorise dans un pays, ajout du lien vers le paiement
  externe directement dans l'app.

## Maquette

`maquette/index.html` (validée) : ouvre-la dans un navigateur (sur téléphone de préférence).
Données fictives, heure simulée à 20:10 GMT. Lien direct vers une rubrique
avec `#id`, par exemple `index.html#score`.

## Le nom

**Buteo** est le nom latin de la buse, un rapace connu pour sa vue perçante.
On y entend aussi **« but »**. L'idée : un œil de rapace posé sur chaque match.

## Le logo

![Aperçu de la marque](marque/apercu-marque.png)

Un œil de rapace dont l'iris est un ballon. Le sourcil doré donne le regard
du prédateur et rappelle le trophée.

| Fichier | Usage |
|---|---|
| `marque/buteo-logo.svg` | Logo horizontal sur fond sombre |
| `marque/buteo-logo-clair.svg` | Logo horizontal sur fond clair |
| `marque/buteo-icone.svg` | Icône d'application (coins arrondis) |
| `marque/buteo-icone-carree.svg` | Icône carrée (Android adaptatif, stores) |
| `marque/buteo-icone-512.png` | Icône Google Play (512 × 512) |
| `marque/buteo-symbole.svg` | Symbole seul (écran de démarrage, favicon) |
| `marque/generer_logo.py` | Script qui régénère les SVG |

## Palette

| Nom | Couleur | Usage |
|---|---|---|
| Nuit | `#0A1230` | Fond principal |
| Victoire | `#2BF59A` | Pronostic gagné, actions principales |
| Or | `#FFC53D` | Offres VIP, mises en avant |
| Perdu | `#FF4D6A` | Pronostic perdu, alertes |

Polices : **Inter** pour le texte et **Barlow Condensed** pour les chiffres
(scores, cotes), toutes deux sous licence libre OFL.
