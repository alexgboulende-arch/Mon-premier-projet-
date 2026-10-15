# Fiche Play Store de Buteo

Tout ce qu'il faut copier dans la Play Console, dans l'ordre où elle le demande.

## Fiche principale (Croissance → Présentation sur le Play Store)

**Nom de l'application** (30 caractères au plus) :

```
Buteo – Pronostics foot IA
```

**Description courte** (80 caractères au plus) :

```
Pronos foot par IA chaque jour à 00:00, résultats en direct et concours.
```

**Description complète** (4 000 caractères au plus) :

```
Buteo publie chaque nuit à 00:00 GMT les pronostics de football calculés par son intelligence artificielle, avec pour chacun un indice de confiance.

COMMENT ÇA MARCHE
L'IA de Buteo estime la force de chaque équipe à partir de ses résultats récents, calcule la probabilité de chaque score, puis la compare aux cotes du marché. Chaque prono affiche sa cote et un indice de confiance : la probabilité estimée qu'il passe.

5 RUBRIQUES GRATUITES CHAQUE JOUR
• Sélection du jour : les pronos les plus sûrs
• Combiné du jour
• Plus / moins de buts
• Les deux équipes marquent
• Bonus surprise
Et le prono phare : la confiance la plus haute de l'IA. Basket et tennis arrivent bientôt.

RÉSULTATS EN DIRECT ET HISTORIQUE COMPLET
Les scores se mettent à jour pendant les matchs. Chaque prono gagné ou perdu reste visible : statistiques de réussite par rubrique, sur 7 et 30 jours, en toute transparence.

CONCOURS DU JOUR
Chaque jour, 5 grands matchs : prédis 1, N ou 2 avant le coup d'envoi. Une bonne réponse rapporte sa cote × 10 points. Grimpe au classement de la semaine et du mois, gagne des badges (champion, podium, sans faute). Aucun argent en jeu.

JOURNAL DE PARIS
Note tes paris et suis ton bénéfice, ton rendement et ta réussite.

MES ÉQUIPES ET ALERTES
Suis tes équipes : leurs matchs du jour apparaissent sur l'accueil. Alertes à la publication des pronos et à chaque résultat.

FORMULES PRO ET ÉLITE
Rubriques VIP (score exact, mi-temps / fin, combinés cote 5+ et 10+, simples VIP), sans publicité. Ou un coupon pour débloquer une rubrique VIP pour la journée.

CHAMPIONNATS
Ligue 1, Premier League, LaLiga, Serie A, Bundesliga, Ligue des champions, Ligue Europa, et des championnats africains : Côte d'Ivoire, Sénégal, Cameroun, Maroc, Tunisie, Algérie, Ligue des champions CAF.

IMPORTANT
Buteo est une application d'information. Elle ne propose aucun pari et ne renvoie vers aucun site de paris. Les pronostics ne garantissent aucun gain. Réservé aux plus de 18 ans. Joue avec modération.
```

**Éléments graphiques** (dossier `buteo/store/`) :

| Élément | Fichier |
|---|---|
| Icône (512 × 512) | `icone-512.png` |
| Image de présentation (1024 × 500) | `image-presentation.png` |
| Captures d'écran du téléphone (1080 × 1920) | `captures/1-accueil.png` à `captures/6-journal.png`, dans cet ordre |

Pour refaire les captures après un changement d'écran (dans `buteo/app`) :
`BUTEO_CAPTURES=1 flutter test test/captures_test.dart --update-goldens`.

**Catégorie** : Sports. **Tags** : Football, Sports.

**Coordonnées** : une adresse e-mail de contact (publique ; une adresse Gmail
dédiée à Buteo convient), et le site : `https://buteo-bbec5.web.app`.

## Contenu de l'application (Règles → Contenu de l'application)

| Rubrique | Réponse |
|---|---|
| Règles de confidentialité | `https://buteo-bbec5.web.app/confidentialite.html` |
| Accès à l'application | Tout est accessible sans connexion, sauf le concours et la synchronisation du compte (connexion Google). Pas besoin d'identifiants de test. |
| Annonces | Oui, l'application contient des annonces (AdMob, version gratuite). |
| Classification du contenu | Questionnaire IARC, catégorie « Référence, actualités ou éducation ». Répondre honnêtement : pas de violence, pas de contenu sexuel ; **références aux jeux d'argent : oui** (pronostics sur des matchs) ; **jeux d'argent réels ou simulés dans l'app : non** ; achats numériques : oui. |
| Public cible | 18 ans et plus uniquement. |
| Application d'actualités | Non. |
| Applications liées à la santé, finance, gouvernement | Non (aucune fonctionnalité financière : les achats sont des abonnements numériques). |
| Suppression des données | Lien : `https://buteo-bbec5.web.app/suppression-compte.html` ; suppression aussi possible dans l'app (Profil → Supprimer mon compte). |

### Sécurité des données

Chiffrement en transit : **oui**. Suppression des données à la demande : **oui**.
Aucune donnée n'est vendue. Données déclarées :

| Type de données | Collectée | Partagée | Pourquoi | Facultative |
|---|---|---|---|---|
| Nom, adresse e-mail, ID utilisateur | Oui | Non | Gestion du compte | Oui (connexion facultative) |
| Historique des achats | Oui | Non | Fonctionnalités de l'app (débloquer les formules) | Oui |
| Interactions dans l'app (équipes suivies, pronos du concours, journal) | Oui | Non | Fonctionnalités de l'app | Oui |
| Identifiants de l'appareil (identifiant publicitaire, jeton de notification) | Oui | Oui (AdMob) | Publicité, notifications | Non |
| Plantages et diagnostics | Non | | | |
| Position, contacts, photos, messages | Non | | | |

## Publication

1. **Test interne** : envoie le fichier `.aab` (Actions → dernière construction
   → `buteo-play-store`), ajoute ton adresse comme testeur, installe depuis le
   lien d'inscription. Vérifie la connexion Google (empreintes SHA de la
   « clé de signature de l'app » ajoutées dans Firebase) et un achat de test.
2. **Test fermé** (obligatoire pour un compte personnel) : **12 testeurs**
   minimum, inscrits pendant **14 jours d'affilée**. Crée un Groupe Google
   (groups.google.com) ou une liste d'adresses Gmail, partage le lien
   d'inscription (WhatsApp), et demande-leur d'ouvrir l'app de temps en temps
   et de laisser un avis privé.
3. **Accès à la production** : au bout des 14 jours, Play Console → Tableau de
   bord → « Demander l'accès à la production », puis réponds au questionnaire
   (comment le test s'est passé, ce qui a été corrigé).
4. **Production** : nouvelle version avec le `.aab`, notes de version, pays
   (commence par le Gabon et l'Afrique francophone), puis « Lancer ».

**Notes de version** (exemple) :

```
Première version de Buteo : pronos foot par IA chaque jour à 00:00, résultats en direct, concours du jour et journal de paris.
```
