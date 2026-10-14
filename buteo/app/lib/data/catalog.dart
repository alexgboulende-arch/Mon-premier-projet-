import 'package:flutter/material.dart';

import 'models.dart';

/// Les 13 rubriques validées sur la maquette.
const rubrics = <Rubric>[
  Rubric(
    id: 'selection',
    name: 'Sélection du jour',
    icon: Icons.star_outline_rounded,
    tier: Tier.free,
    markets: ['1', '1X', 'X2', 'o15'],
    count: 3,
  ),
  Rubric(
    id: 'combine',
    name: 'Combiné du jour',
    icon: Icons.layers_outlined,
    tier: Tier.free,
    markets: ['1X', 'o15', 'X2', 'u35'],
    comboLegs: 3,
  ),
  Rubric(
    id: 'overunder',
    name: 'Plus / Moins de buts',
    icon: Icons.exposure_outlined,
    tier: Tier.free,
    markets: ['o25', 'u35', 'o15', 'u25'],
    count: 4,
  ),
  Rubric(
    id: 'btts',
    name: 'Les deux marquent',
    icon: Icons.swap_horiz_rounded,
    tier: Tier.free,
    markets: ['by', 'bn'],
    count: 3,
  ),
  Rubric(
    id: 'basket',
    name: 'Basket',
    icon: Icons.sports_basketball_outlined,
    tier: Tier.free,
    sport: Sport.basket,
    markets: ['bw', 'bh', 'bt'],
    count: 3,
    engine: false,
  ),
  Rubric(
    id: 'tennis',
    name: 'Tennis',
    icon: Icons.sports_tennis_outlined,
    tier: Tier.free,
    sport: Sport.tennis,
    markets: ['tw', 't3', 'ts'],
    count: 3,
    engine: false,
  ),
  Rubric(
    id: 'bonus',
    name: 'Bonus surprise',
    icon: Icons.card_giftcard_outlined,
    tier: Tier.free,
    markets: ['o35', '2'],
    count: 1,
    wide: true,
  ),
  Rubric(
    id: 'score',
    name: 'Score exact',
    icon: Icons.track_changes_rounded,
    tier: Tier.elite,
    markets: ['cs'],
    count: 2,
  ),
  Rubric(
    id: 'htft',
    name: 'Mi-temps / Fin',
    icon: Icons.timelapse_rounded,
    tier: Tier.pro,
    markets: ['htft'],
    count: 2,
  ),
  Rubric(
    id: 'c5',
    name: 'Combiné cote 5+',
    icon: Icons.layers_outlined,
    tier: Tier.elite,
    markets: ['1', '1X', 'X2', 'o15', 'o25', 'by'],
    comboLegs: 4,
    comboMin: 5,
  ),
  Rubric(
    id: 'c10',
    name: 'Combiné cote 10+',
    icon: Icons.layers_outlined,
    tier: Tier.pro,
    markets: ['1', '2', 'o25', 'by', 'u25'],
    comboLegs: 5,
    comboMin: 10,
  ),
  Rubric(
    id: 'simples',
    name: 'Simples VIP',
    icon: Icons.confirmation_number_outlined,
    tier: Tier.pro,
    markets: ['1', '2', 'o25', 'by'],
    count: 3,
  ),
  Rubric(
    id: 'live',
    name: 'Live',
    icon: Icons.bolt_rounded,
    tier: Tier.elite,
    markets: ['o15', 'o25', 'by'],
    count: 2,
    live: true,
    engine: false,
  ),
];

final rubricsById = {for (final r in rubrics) r.id: r};
final freeRubrics = rubrics.where((r) => !r.isVip).toList();
final vipRubrics = rubrics.where((r) => r.isVip).toList();

/// Prix en FCFA et équivalent indicatif en euros.
typedef Price = ({int fcfa, String euros});

class Plan {
  const Plan({required this.tier, required this.perks, this.prices = const {}, this.tag});

  final Tier tier;
  final List<String> perks;

  /// Prix par durée d'abonnement, en mois.
  final Map<int, Price> prices;
  final String? tag;
}

const plans = <Plan>[
  Plan(
    tier: Tier.free,
    perks: ['Les 7 rubriques gratuites chaque jour', 'Historique et statistiques complets', 'Avec publicités'],
  ),
  Plan(
    tier: Tier.pro,
    tag: 'Recommandé',
    prices: {1: (fcfa: 2900, euros: '4,49'), 3: (fcfa: 7500, euros: '11,49'), 6: (fcfa: 13900, euros: '20,99')},
    perks: [
      'Tout le gratuit, sans publicité',
      'Simples VIP, Mi-temps / Fin, Combiné cote 10+',
      'Alerte dès la publication à 00:00',
    ],
  ),
  Plan(
    tier: Tier.elite,
    prices: {1: (fcfa: 6900, euros: '10,49'), 3: (fcfa: 17900, euros: '27,49'), 6: (fcfa: 32900, euros: '49,99')},
    perks: ['Tout Pro', 'Score exact, Combiné cote 5+, Live', 'Alertes pendant les matchs en direct'],
  ),
];

/// Coupon VIP à l'unité : une rubrique débloquée pour la journée.
const Price couponPrice = (fcfa: 500, euros: '0,79');
