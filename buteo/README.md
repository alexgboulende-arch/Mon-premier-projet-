# Buteo — Pronostics sportifs

Application mobile de pronostics sportifs inspirée de *Multi Betting Tips*, en
version améliorée. **Statut : maquette cliquable à valider.**

## Décisions prises

- Vrai business, Android d'abord, en français, pour le monde francophone.
- Pronostics produits par une **IA**, publiés à **00:00**, avec un indice de confiance.
- Résultats mis à jour automatiquement, historique complet (gagnés et perdus).
- Revenus : coupon VIP à l'unité, publicité dans la version gratuite, abonnements Pro et Élite.
- Pas de liens vers les bookmakers.
- Étapes : maquette cliquable, puis vraie app en Flutter.

## Maquette

`maquette/index.html` : ouvre-la dans un navigateur (sur téléphone de préférence).
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

Police : **Inter** (libre de droits, licence OFL).
