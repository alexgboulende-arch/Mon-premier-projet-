import 'dart:math' as math;

import 'catalog.dart';
import 'models.dart';

/// Source des pronostics. La version de démonstration génère des données
/// fictives ; la vraie version lira les pronos publiés par l'IA (Firebase).
abstract class TipsRepository {
  /// Heure actuelle, en GMT.
  DateTime now();

  RubricDay day(Rubric rubric, DateTime date);

  /// Championnats et équipes suivis par l'IA.
  List<TeamGroup> teamGroups();
}

/// Pronos fictifs mais stables : une même rubrique et une même date
/// donnent toujours les mêmes matchs et les mêmes résultats.
class DemoTipsRepository implements TipsRepository {
  DemoTipsRepository({DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final _cache = <String, RubricDay>{};

  @override
  DateTime now() => _clock();

  @override
  List<TeamGroup> teamGroups() => [
    for (final (sport, leagues) in [(Sport.foot, _foot), (Sport.basket, _basket), (Sport.tennis, _tennis)])
      for (final l in leagues) TeamGroup(sport: sport, league: l.name, country: l.country, teams: l.teams),
  ];

  @override
  RubricDay day(Rubric rubric, DateTime date) {
    final key = '${rubric.id}|${dateKey(date)}';
    return _cache.putIfAbsent(key, () => _generate(rubric, key));
  }

  RubricDay _generate(Rubric rubric, String key) {
    final base = fnv1a(key);
    final r = Rng(base);
    if (rubric.isCombo) {
      final legs = <Tip>[];
      final rngs = <Rng>[];
      for (var i = 0; i < rubric.comboLegs; i++) {
        final tr = Rng(base + i * 7919);
        final t = _makeTip(tr, r.pick(rubric.markets), Sport.foot);
        t.time = _slots[(base + i * 2) % _slots.length];
        legs.add(t);
        rngs.add(tr);
      }
      final product = legs.fold<double>(1, (p, l) => p * l.odds);
      if (rubric.comboMin > 0 && product < rubric.comboMin) {
        final f = math.pow(rubric.comboMin * 1.03 / product, 1 / legs.length);
        for (final l in legs) {
          l.odds = (l.odds * f * 100).round() / 100;
        }
      }
      for (var i = 0; i < legs.length; i++) {
        _settle(legs[i], rngs[i]);
      }
      legs.sort((a, b) => a.kickoff.compareTo(b.kickoff));
      return RubricDay(combo: Combo(legs));
    }
    final tips = <Tip>[];
    for (var i = 0; i < rubric.count; i++) {
      final tr = Rng(base + i * 7919);
      final t = _makeTip(tr, r.pick(rubric.markets), rubric.sport);
      _settle(t, tr);
      t.time = rubric.live ? const ['19:00', '19:45'][i % 2] : _slots[(base + i * 4) % _slots.length];
      tips.add(t);
    }
    tips.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    return RubricDay(tips: tips);
  }

  Tip _makeTip(Rng r, String market, Sport sport) {
    final pool = switch (sport) {
      Sport.foot => _foot,
      Sport.basket => _basket,
      Sport.tennis => _tennis,
    };
    final league = r.pick(pool);
    final i = (r.next() * league.teams.length).floor();
    var j = (r.next() * (league.teams.length - 1)).floor();
    if (j >= i) j++;
    final fixture = Fixture(
      league: league.name,
      country: league.country,
      home: league.teams[i],
      away: league.teams[j],
      sport: sport,
      target: market == 'cs'
          ? r.pick(const [
              [1, 0],
              [2, 1],
              [1, 1],
              [2, 0],
              [0, 1],
              [1, 2],
            ])
          : null,
    );
    final m = markets[market]!;
    final odds = ((m.min + r.next() * (m.max - m.min)) * 100).round() / 100;
    return Tip(fixture: fixture, market: market, label: m.label(fixture), odds: odds);
  }

  /// L'indice de confiance est la probabilité estimée par l'IA ;
  /// le résultat fictif suit cette probabilité.
  void _settle(Tip t, Rng r) {
    final c = ((1 / t.odds + .03 + r.next() * .06) * 100).round();
    t.confidence = c.clamp(8, 93);
    final want = r.next() < t.confidence / 100;
    final check = markets[t.market]!.check;
    var s = _sample(t.fixture.sport, r);
    for (var k = 0; k < 300 && check(s, t.fixture) != want; k++) {
      s = _sample(t.fixture.sport, r);
    }
    t.score = s;
    t.won = check(s, t.fixture);
  }

  Score _sample(Sport sport, Rng r) {
    switch (sport) {
      case Sport.foot:
        int goals() {
          final x = r.next();
          return x < .24
              ? 0
              : x < .57
              ? 1
              : x < .80
              ? 2
              : x < .92
              ? 3
              : x < .97
              ? 4
              : 5;
        }
        List<int> minutes(int n) =>
            List.generate(n, (_) => r.next() < .45 ? 1 + (r.next() * 45).floor() : 46 + (r.next() * 45).floor());
        final gh = minutes(goals());
        final ga = minutes(goals());
        return Score(gh.length, ga.length, goalsHome: gh, goalsAway: ga);
      case Sport.basket:
        var h = 96 + (r.next() * 30).floor();
        final a = 94 + (r.next() * 30).floor();
        if (h == a) h++;
        return Score(h, a);
      case Sport.tennis:
        final x = r.next();
        final s = x < .38
            ? const [2, 0]
            : x < .62
            ? const [2, 1]
            : x < .82
            ? const [1, 2]
            : const [0, 2];
        return Score(s[0], s[1]);
    }
  }
}

/// Durée d'un match, en minutes, pour savoir s'il est terminé.
const matchDuration = {Sport.foot: 112, Sport.basket: 150, Sport.tennis: 125};

/// État d'un prono à l'heure [now] (GMT). [date] est le jour du match.
TipStatus statusOf(Tip t, DateTime date, DateTime now) {
  final today = dayOf(now);
  final d = dayOf(date);
  if (d.isBefore(today)) return _final(t);
  if (d.isAfter(today)) return const TipStatus(StatusKind.soon);
  final elapsed = now.hour * 60 + now.minute - t.kickoff;
  final sport = t.fixture.sport;
  final duration = matchDuration[sport]!;
  if (elapsed < 0) return const TipStatus(StatusKind.soon);
  if (elapsed >= duration) return _final(t);
  switch (sport) {
    case Sport.foot:
      final int at;
      final String label;
      if (elapsed <= 47) {
        at = math.max(1, elapsed);
        label = "$at'";
      } else if (elapsed < 62) {
        at = 45;
        label = 'MT';
      } else {
        at = math.min(90, elapsed - 17);
        label = "$at'";
      }
      return TipStatus(
        StatusKind.live,
        label: label,
        home: t.score.goalsHome.where((m) => m <= at).length,
        away: t.score.goalsAway.where((m) => m <= at).length,
      );
    case Sport.basket:
      final f = elapsed / duration;
      return TipStatus(
        StatusKind.live,
        label: 'Q${math.min(4, 1 + (f * 4).floor())}',
        home: (t.score.home * f).round(),
        away: (t.score.away * f).round(),
      );
    case Sport.tennis:
      final s = t.score;
      final order = s.home > s.away
          ? (s.away > 0 ? const ['h', 'a', 'h'] : const ['h', 'h'])
          : (s.home > 0 ? const ['a', 'h', 'a'] : const ['a', 'a']);
      final done = order.take((order.length * elapsed / duration).floor()).toList();
      return TipStatus(
        StatusKind.live,
        label: 'Set ${done.length + 1}',
        home: done.where((x) => x == 'h').length,
        away: done.where((x) => x == 'a').length,
      );
  }
}

TipStatus _final(Tip t) => TipStatus(t.won ? StatusKind.won : StatusKind.lost, home: t.score.home, away: t.score.away);

/// État d'un combiné : perdu dès qu'un match est perdu, gagné quand tous sont gagnés.
TipStatus comboStatus(Combo c, DateTime date, DateTime now) {
  final all = c.legs.map((l) => statusOf(l, date, now)).toList();
  if (all.any((s) => s.kind == StatusKind.lost)) return const TipStatus(StatusKind.lost);
  if (all.every((s) => s.kind == StatusKind.won)) return const TipStatus(StatusKind.won);
  if (all.any((s) => s.kind == StatusKind.live)) return const TipStatus(StatusKind.live, label: 'En cours');
  return const TipStatus(StatusKind.soon);
}

class PickStats {
  const PickStats({this.count = 0, this.won = 0, this.oddsSum = 0, this.profit = 0});

  final int count;
  final int won;
  final double oddsSum;

  /// Gain net en misant 1 unité sur chaque prono.
  final double profit;

  double get rate => count == 0 ? 0 : won / count;
  double get averageOdds => count == 0 ? 0 : oddsSum / count;

  /// Rendement : gain net divisé par le total misé.
  double get roi => count == 0 ? 0 : profit / count;

  PickStats operator +(PickStats o) =>
      PickStats(count: count + o.count, won: won + o.won, oddsSum: oddsSum + o.oddsSum, profit: profit + o.profit);

  static PickStats of(Iterable<Pick> picks) {
    var s = const PickStats();
    for (final p in picks) {
      s = s + PickStats(count: 1, won: p.won ? 1 : 0, oddsSum: p.odds, profit: p.won ? p.odds - 1 : -1);
    }
    return s;
  }
}

/// Statistiques des [days] derniers jours, aujourd'hui exclu.
PickStats statsFor(TipsRepository repo, Rubric rubric, int days) {
  final today = dayOf(repo.now());
  var s = const PickStats();
  for (var d = 1; d <= days; d++) {
    s = s + PickStats.of(repo.day(rubric, today.subtract(Duration(days: d))).picks);
  }
  return s;
}

PickStats globalStats(TipsRepository repo, int days) =>
    rubrics.fold(const PickStats(), (s, r) => s + statsFor(repo, r, days));

/// Taux de réussite de toutes les rubriques pour une journée passée.
double dayRate(TipsRepository repo, DateTime date) => PickStats.of(rubrics.expand((r) => repo.day(r, date).picks)).rate;

DateTime dayOf(DateTime t) => DateTime.utc(t.year, t.month, t.day);

String dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Marchés : libellé, fourchette de cote, règle de validation.

class Market {
  const Market(this.label, this.min, this.max, this.check);

  final String Function(Fixture f) label;
  final double min;
  final double max;
  final bool Function(Score s, Fixture f) check;
}

final markets = <String, Market>{
  '1': Market((f) => 'Victoire ${f.home}', 1.45, 2.10, (s, f) => s.home > s.away),
  '2': Market((f) => 'Victoire ${f.away}', 1.70, 2.60, (s, f) => s.away > s.home),
  '1X': Market((f) => '${f.home} ou nul', 1.20, 1.45, (s, f) => s.home >= s.away),
  'X2': Market((f) => '${f.away} ou nul', 1.25, 1.55, (s, f) => s.away >= s.home),
  'o15': Market((f) => 'Plus de 1,5 buts', 1.20, 1.40, (s, f) => s.home + s.away >= 2),
  'o25': Market((f) => 'Plus de 2,5 buts', 1.55, 1.95, (s, f) => s.home + s.away >= 3),
  'o35': Market((f) => 'Plus de 3,5 buts', 2.30, 3.20, (s, f) => s.home + s.away >= 4),
  'u25': Market((f) => 'Moins de 2,5 buts', 1.60, 2.00, (s, f) => s.home + s.away <= 2),
  'u35': Market((f) => 'Moins de 3,5 buts', 1.25, 1.45, (s, f) => s.home + s.away <= 3),
  'by': Market((f) => 'Les deux marquent : oui', 1.60, 1.90, (s, f) => s.home > 0 && s.away > 0),
  'bn': Market((f) => 'Les deux marquent : non', 1.75, 2.05, (s, f) => !(s.home > 0 && s.away > 0)),
  'cs': Market(
    (f) => 'Score exact ${f.target![0]}-${f.target![1]}',
    6.50,
    9.50,
    (s, f) => s.home == f.target![0] && s.away == f.target![1],
  ),
  'htft': Market(
    (f) => '${f.home} mène à la pause et gagne',
    2.80,
    3.60,
    (s, f) => s.halfTimeHome > s.halfTimeAway && s.home > s.away,
  ),
  'bw': Market((f) => 'Victoire ${f.home}', 1.35, 1.85, (s, f) => s.home > s.away),
  'bh': Market((f) => '${f.home} handicap −5,5', 1.80, 1.95, (s, f) => s.home - s.away > 5.5),
  'bt': Market((f) => 'Plus de 214,5 points', 1.80, 1.95, (s, f) => s.home + s.away > 214.5),
  'tw': Market((f) => 'Victoire ${f.home}', 1.30, 1.90, (s, f) => s.home > s.away),
  't3': Market((f) => 'Match en 3 sets', 2.00, 2.40, (s, f) => s.home + s.away == 3),
  'ts': Market((f) => '${f.away} gagne au moins un set', 1.60, 2.10, (s, f) => s.away >= 1),
};

// ---------------------------------------------------------------------------
// Données fictives.

class _League {
  const _League(this.name, this.country, this.teams);

  final String name;
  final String country;
  final List<String> teams;
}

const _foot = [
  _League('Ligue 1', 'France', ['PSG', 'Marseille', 'Lyon', 'Monaco', 'Lille', 'Lens', 'Rennes', 'Nice']),
  _League('Premier League', 'Angleterre', [
    'Arsenal',
    'Liverpool',
    'Man City',
    'Chelsea',
    'Tottenham',
    'Newcastle',
    'Aston Villa',
  ]),
  _League('LaLiga', 'Espagne', ['Real Madrid', 'Barcelone', 'Atlético', 'Séville', 'Villarreal', 'Betis']),
  _League('Serie A', 'Italie', ['Inter', 'Milan', 'Juventus', 'Naples', 'Rome', 'Atalanta']),
  _League('Bundesliga', 'Allemagne', ['Bayern', 'Dortmund', 'Leverkusen', 'Leipzig', 'Stuttgart']),
  _League('Ligue 1', "Côte d'Ivoire", ['ASEC Mimosas', 'Africa Sports', "Stade d'Abidjan", 'SOA', 'San Pédro']),
  _League('Elite One', 'Cameroun', ['Coton Sport', 'Canon Yaoundé', 'Union Douala', 'Fovu Baham', 'Colombe']),
  _League('Botola Pro', 'Maroc', ['Raja', 'Wydad', 'FAR Rabat', 'RS Berkane', 'FUS Rabat']),
  _League('Ligue 1', 'Sénégal', ['Jaraaf', 'Teungueth', 'Génération Foot', 'Casa Sports', 'Diambars']),
];

const _basket = [
  _League('NBA', 'États-Unis', ['Lakers', 'Celtics', 'Warriors', 'Bucks', 'Nuggets', 'Knicks', 'Spurs']),
  _League('EuroLeague', 'Europe', ['Real Madrid', 'Monaco', 'Fenerbahçe', 'Olympiakos', 'ASVEL', 'Paris Basketball']),
];

const _tennis = [
  _League('ATP 250', 'Stockholm', [
    'Sinner J.',
    'Alcaraz C.',
    'Zverev A.',
    'Fils A.',
    'Mpetshi Perricard G.',
    'Humbert U.',
    'Rune H.',
    'Shelton B.',
  ]),
  _League('WTA 500', 'Tokyo', [
    'Sabalenka A.',
    'Swiatek I.',
    'Gauff C.',
    'Garcia C.',
    'Paolini J.',
    'Rybakina E.',
    'Andreeva M.',
  ]),
];

const _slots = ['13:00', '15:00', '16:30', '18:00', '19:00', '19:45', '20:00', '21:00', '21:45'];

// ---------------------------------------------------------------------------
// Hasard reproductible (mulberry32) et hachage FNV-1a, comme dans la maquette.

class Rng {
  Rng(int seed) : _a = seed & _mask;

  static const _mask = 0xFFFFFFFF;
  int _a;

  static int _imul(int a, int b) => (a * b) & _mask;

  double next() {
    _a = (_a + 0x6D2B79F5) & _mask;
    var t = _imul(_a ^ (_a >> 15), 1 | _a);
    t = ((t + _imul(t ^ (t >> 7), 61 | t)) & _mask) ^ t;
    return ((t ^ (t >> 14)) & _mask) / 4294967296;
  }

  T pick<T>(List<T> list) => list[(next() * list.length).floor()];
}

int fnv1a(String s) {
  var h = 2166136261;
  for (final u in s.codeUnits) {
    h ^= u;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}
