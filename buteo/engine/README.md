# Moteur de pronostics Buteo

Programme Python qui calcule les pronos de football chaque nuit et suit les
résultats pendant les matchs. Il tourne sur GitHub Actions
(`.github/workflows/buteo-moteur.yml`) et écrit dans Firestore, où l'app lit.

## Comment les pronos sont choisis

1. **Données** : matchs, résultats et cotes viennent d'[API-Football](https://www.api-football.com).
2. **Modèle** (`engine/model.py`) : pour chaque championnat, la force
   d'attaque et de défense de chaque équipe est estimée sur ses résultats
   récents (un match d'il y a six mois compte moitié moins). On en tire la
   probabilité de chaque score (loi de Poisson, correction Dixon-Coles), puis
   de chaque pari.
3. **Mélange avec les bookmakers** (`engine/selection.py`) : la probabilité
   retenue mêle le modèle (35 %) et les cotes des bookmakers sans leur marge
   (65 %). C'est l'**indice de confiance** affiché dans l'app.
4. **Choix par rubrique** : chaque rubrique a sa fourchette de cotes et sa
   confiance minimale ; les rubriques « sûres » prennent les pronos les plus
   probables, les autres ceux dont la cote est la plus intéressante. Les paris
   nettement défavorables sont écartés partout.
5. **Résultats** (`engine/picks.py`) : toutes les 10 minutes, les matchs
   commencés sont mis à jour (score, minute, gagné, perdu, annulé). Un pari
   porte sur le score à 90 minutes ; un match annulé ne compte pas.

Le football couvre 10 rubriques. Basket, tennis et live viendront ensuite.

## Commandes

```bash
pip install -r requirements-dev.txt
python -m pytest                 # tests
python -m engine essai           # essai complet hors ligne, données simulées
python -m engine publier         # pronos du jour (clés nécessaires)
python -m engine resultats       # mise à jour des résultats (clés nécessaires)
```

`exemple_picks.json` est produit par `python -m engine essai --json exemple_picks.json`.
L'app le lit dans ses tests : c'est le contrat entre le moteur et l'app.
