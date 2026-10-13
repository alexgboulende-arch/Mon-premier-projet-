import 'package:flutter/widgets.dart';

enum Sport { foot, basket, tennis }

/// Formules d'accès, de la moins chère à la plus complète.
enum Tier {
  free('Gratuit', 'GRATUIT'),
  pro('Pro', 'PRO'),
  elite('Élite', 'ÉLITE');

  const Tier(this.label, this.badge);
  final String label;
  final String badge;

  bool includes(Tier other) => index >= other.index;
}

/// Une rubrique de pronostics (Sélection du jour, Score exact…).
class Rubric {
  const Rubric({
    required this.id,
    required this.name,
    required this.icon,
    required this.tier,
    this.sport = Sport.foot,
    this.markets = const [],
    this.count = 0,
    this.comboLegs = 0,
    this.comboMin = 0,
    this.live = false,
    this.wide = false,
  });

  final String id;
  final String name;
  final IconData icon;
  final Tier tier;
  final Sport sport;
  final List<String> markets;

  /// Nombre de pronos simples publiés par jour.
  final int count;

  /// Nombre de matchs du combiné (0 si la rubrique n'est pas un combiné).
  final int comboLegs;

  /// Cote totale minimale du combiné.
  final double comboMin;
  final bool live;

  /// Tuile sur toute la largeur de la grille d'accueil.
  final bool wide;

  bool get isCombo => comboLegs > 0;
  bool get isVip => tier != Tier.free;
}

class Fixture {
  const Fixture({
    required this.league,
    required this.country,
    required this.home,
    required this.away,
    required this.sport,
    this.target,
  });

  final String league;
  final String country;
  final String home;
  final String away;
  final Sport sport;

  /// Score visé pour le marché « score exact ».
  final List<int>? target;
}

/// Score final. Pour le foot, la minute de chaque but sert à afficher
/// le score en direct et le score à la mi-temps.
class Score {
  const Score(this.home, this.away, {this.goalsHome = const [], this.goalsAway = const []});

  final int home;
  final int away;
  final List<int> goalsHome;
  final List<int> goalsAway;

  int get halfTimeHome => goalsHome.where((m) => m <= 45).length;
  int get halfTimeAway => goalsAway.where((m) => m <= 45).length;
}

/// Ce qui se compte dans les statistiques : un prono simple ou un combiné entier.
abstract class Pick {
  double get odds;
  bool get won;
  int get confidence;
}

class Tip implements Pick {
  Tip({required this.fixture, required this.market, required this.label, required this.odds, this.time = '00:00'});

  final Fixture fixture;
  final String market;
  final String label;

  @override
  double odds;

  /// Heure du coup d'envoi, en GMT (« 21:00 »).
  String time;

  @override
  int confidence = 0;

  @override
  bool won = false;

  Score score = const Score(0, 0);

  int get kickoff => minutesOf(time);
}

class Combo implements Pick {
  Combo(this.legs);

  final List<Tip> legs;

  @override
  double get odds => (legs.fold<double>(1, (p, l) => p * l.odds) * 100).round() / 100;

  @override
  bool get won => legs.every((l) => l.won);

  /// Probabilité que tous les matchs passent.
  @override
  int get confidence {
    final p = legs.fold<double>(1, (p, l) => p * l.confidence / 100);
    final v = (p * 100).round();
    return v < 1 ? 1 : v;
  }
}

/// Les pronos d'une rubrique pour une journée.
class RubricDay {
  const RubricDay({this.tips = const [], this.combo});

  final List<Tip> tips;
  final Combo? combo;

  bool get isCombo => combo != null;

  /// Pronos comptés dans les statistiques (un combiné compte pour un).
  List<Pick> get picks => combo != null ? [combo!] : tips;

  /// Tous les matchs, combinés compris.
  List<Tip> get allTips => combo?.legs ?? tips;
}

enum StatusKind { soon, live, won, lost }

class TipStatus {
  const TipStatus(this.kind, {this.label, this.home, this.away});

  final StatusKind kind;

  /// « 63' », « MT », « Q3 », « Set 2 », « En cours ».
  final String? label;
  final int? home;
  final int? away;

  bool get hasScore => home != null && away != null;
  bool get finished => kind == StatusKind.won || kind == StatusKind.lost;
}

int minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
