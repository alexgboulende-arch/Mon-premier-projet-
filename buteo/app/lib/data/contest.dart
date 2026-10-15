import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'catalog.dart';
import 'tips_repository.dart';

/// Concours « Pronos du jour » : 5 matchs, chacun prédit 1, N ou 2.
/// Un bon prono rapporte sa cote × 10 points. Publié et noté par le moteur
/// (`buteo/engine/engine/contest.py`).
const contestChoices = ['1', 'X', '2'];

String choiceLabel(String c) => c == 'X' ? 'N' : c;

/// Pseudo accepté par les règles Firestore : 3 à 20 lettres, chiffres, espaces, « . _ - ».
final _pseudoPattern = RegExp(r'^[\p{L}\p{N} ._-]{3,20}$', unicode: true);
bool validPseudo(String p) => _pseudoPattern.hasMatch(p.trim());

class ContestMatch {
  const ContestMatch({
    required this.fixtureId,
    required this.league,
    required this.country,
    required this.home,
    required this.away,
    required this.kickoff,
    required this.odds,
    this.result,
    this.score,
  });

  final int fixtureId;
  final String league;
  final String country;
  final String home;
  final String away;
  final DateTime kickoff;
  final Map<String, double> odds;

  /// « 1 », « X », « 2 », « void » (match annulé), ou null tant que le match n'est pas fini.
  final String? result;
  final ({int home, int away})? score;

  bool isOpen(DateTime now) => now.isBefore(kickoff);
  bool get settled => result != null;
  int pointsFor(String choice) => ((odds[choice] ?? 0) * 10).round();

  factory ContestMatch.fromMap(Map<String, dynamic> m) {
    final score = m['score'];
    return ContestMatch(
      fixtureId: (m['fixtureId'] as num).toInt(),
      league: m['league'] as String? ?? '',
      country: m['country'] as String? ?? '',
      home: m['home'] as String,
      away: m['away'] as String,
      kickoff: DateTime.parse(m['kickoff'] as String).toUtc(),
      odds: {for (final e in (m['odds'] as Map).entries) e.key as String: (e.value as num).toDouble()},
      result: m['result'] as String?,
      score: score is Map ? (home: (score['home'] as num).toInt(), away: (score['away'] as num).toInt()) : null,
    );
  }
}

class ContestDay {
  const ContestDay({required this.date, required this.matches});

  final String date;
  final List<ContestMatch> matches;

  factory ContestDay.fromMap(Map<String, dynamic> m) => ContestDay(
    date: m['date'] as String,
    matches: [
      for (final x in m['matches'] as List? ?? const []) ContestMatch.fromMap(Map<String, dynamic>.from(x as Map)),
    ],
  );
}

class LeaderRow {
  const LeaderRow({
    required this.uid,
    required this.pseudo,
    required this.points,
    required this.correct,
    required this.played,
    required this.rank,
  });

  final String uid;
  final String pseudo;
  final int points;
  final int correct;
  final int played;
  final int rank;

  factory LeaderRow.fromMap(Map<String, dynamic> m) => LeaderRow(
    uid: m['uid'] as String,
    pseudo: m['pseudo'] as String? ?? 'Joueur',
    points: (m['points'] as num? ?? 0).toInt(),
    correct: (m['correct'] as num? ?? 0).toInt(),
    played: (m['played'] as num? ?? 0).toInt(),
    rank: (m['rank'] as num? ?? 0).toInt(),
  );
}

/// Rang et points d'un joueur sur une période.
typedef Standing = ({String period, int points, int rank, int correct, int played});

Standing? _standing(Object? m) => m is Map
    ? (
        period: m['period'] as String? ?? '',
        points: (m['points'] as num? ?? 0).toInt(),
        rank: (m['rank'] as num? ?? 0).toInt(),
        correct: (m['correct'] as num? ?? 0).toInt(),
        played: (m['played'] as num? ?? 0).toInt(),
      )
    : null;

class PlayerProfile {
  const PlayerProfile({
    required this.pseudo,
    this.week,
    this.month,
    this.perfectDays = 0,
    this.regularWeeks = 0,
    this.podiums = 0,
    this.championships = 0,
  });

  final String pseudo;
  final Standing? week;
  final Standing? month;

  /// Badges : journées sans faute, semaines jouées tous les jours, podiums, victoires.
  final int perfectDays;
  final int regularWeeks;
  final int podiums;
  final int championships;

  factory PlayerProfile.fromMap(Map<String, dynamic> m) {
    int count(String k) => (m[k] as List?)?.length ?? 0;
    return PlayerProfile(
      pseudo: m['pseudo'] as String? ?? 'Joueur',
      week: _standing(m['week']),
      month: _standing(m['month']),
      perfectDays: count('perfectDays'),
      regularWeeks: count('regularWeeks'),
      podiums: count('podiumWeeks'),
      championships: count('championWeeks'),
    );
  }
}

/// Semaine ISO (« 2026-W42 ») et mois (« 2026-10 ») d'une journée, comme le moteur.
String weekId(DateTime day) {
  final d = DateTime.utc(day.year, day.month, day.day);
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final week = ((thursday.difference(DateTime.utc(thursday.year)).inDays) ~/ 7) + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

String monthId(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}';

/// Accès aux données du concours (Firestore, ou en mémoire pour la démonstration et les tests).
abstract class ContestRepository {
  Stream<ContestDay?> day(String date);
  Stream<List<LeaderRow>> leaderboard(String id);
  Stream<PlayerProfile?> player(String uid);
  Future<Map<int, String>> myPicks(String date, String uid);

  /// Refusé par les règles après le coup d'envoi.
  Future<void> pick(String date, String uid, int fixtureId, String choice, String pseudo);
}

class FirestoreContestRepository implements ContestRepository {
  FirestoreContestRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<ContestDay?> day(String date) =>
      _db.doc('contests/$date').snapshots().map((s) => s.exists ? ContestDay.fromMap(s.data()!) : null);

  @override
  Stream<List<LeaderRow>> leaderboard(String id) => _db
      .doc('leaderboards/$id')
      .snapshots()
      .map(
        (s) => [
          for (final p in s.data()?['players'] as List? ?? const [])
            LeaderRow.fromMap(Map<String, dynamic>.from(p as Map)),
        ],
      );

  @override
  Stream<PlayerProfile?> player(String uid) =>
      _db.doc('contestPlayers/$uid').snapshots().map((s) => s.exists ? PlayerProfile.fromMap(s.data()!) : null);

  @override
  Future<Map<int, String>> myPicks(String date, String uid) async {
    final snap = await _db.collection('contests/$date/picks').where('uid', isEqualTo: uid).get();
    return {for (final d in snap.docs) (d['fixtureId'] as num).toInt(): d['choice'] as String};
  }

  @override
  Future<void> pick(String date, String uid, int fixtureId, String choice, String pseudo) =>
      _db.doc('contests/$date/picks/${uid}_$fixtureId').set({
        'uid': uid,
        'fixtureId': fixtureId,
        'choice': choice,
        'pseudo': pseudo.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

/// Concours en mémoire : démonstration (à partir des pronos simulés) et tests.
class MemoryContestRepository implements ContestRepository {
  MemoryContestRepository({this.contest, List<LeaderRow>? week, List<LeaderRow>? month, this.profile, this.clock})
    : week = week ?? const [],
      month = month ?? const [];

  /// Concours de démonstration : les matchs de la Sélection et du Combiné du jour.
  factory MemoryContestRepository.demo(TipsRepository repo) {
    final now = repo.now();
    final today = dayOf(now);
    final seen = <String>{};
    final matches = <ContestMatch>[];
    for (final id in ['selection', 'combine', 'overunder', 'btts']) {
      final rubric = rubricsById[id];
      if (rubric == null) continue;
      for (final t in repo.day(rubric, today).allTips) {
        final key = '${t.fixture.home}|${t.fixture.away}';
        if (matches.length >= 5 || !seen.add(key)) continue;
        final r = Rng(fnv1a(key));
        final home = 1.4 + r.next() * 2.2;
        final kickoff = today.add(Duration(minutes: t.kickoff));
        matches.add(
          ContestMatch(
            fixtureId: fnv1a(key) & 0x7fffffff,
            league: t.fixture.league,
            country: t.fixture.country,
            home: t.fixture.home,
            away: t.fixture.away,
            kickoff: kickoff,
            odds: {'1': _round(home), 'X': _round(3.0 + r.next() * 0.6), '2': _round(7.2 - home)},
          ),
        );
      }
    }
    matches.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    const names = ['Kofi', 'Mariam', 'Ibou', 'Fatou', 'Junior', 'Aïcha', 'Yao', 'Moussa'];
    final rows = [
      for (final (i, n) in names.indexed)
        LeaderRow(uid: 'demo$i', pseudo: n, points: 160 - i * 17, correct: 9 - i, played: 15, rank: i + 1),
    ];
    return MemoryContestRepository(
      contest: ContestDay(date: dateKey(today), matches: matches),
      week: rows,
      month: [
        for (final r in rows)
          LeaderRow(
            uid: r.uid,
            pseudo: r.pseudo,
            points: r.points * 3,
            correct: r.correct * 3,
            played: 45,
            rank: r.rank,
          ),
      ],
      clock: repo.now,
    );
  }

  static double _round(double x) => (x * 100).round() / 100;

  ContestDay? contest;
  List<LeaderRow> week;
  List<LeaderRow> month;
  PlayerProfile? profile;
  final DateTime Function()? clock;
  final picks = <String, Map<int, String>>{};

  @override
  Stream<ContestDay?> day(String date) => Stream.value(contest?.date == date ? contest : null);

  @override
  Stream<List<LeaderRow>> leaderboard(String id) => Stream.value(id.startsWith('week-') ? week : month);

  @override
  Stream<PlayerProfile?> player(String uid) => Stream.value(profile);

  @override
  Future<Map<int, String>> myPicks(String date, String uid) async => {...?picks['$date|$uid']};

  @override
  Future<void> pick(String date, String uid, int fixtureId, String choice, String pseudo) async {
    final match = contest?.matches.where((m) => m.fixtureId == fixtureId).firstOrNull;
    final now = clock?.call() ?? DateTime.now().toUtc();
    if (match == null || !match.isOpen(now)) throw StateError('Pronos fermés pour ce match.');
    (picks['$date|$uid'] ??= {})[fixtureId] = choice;
  }
}
