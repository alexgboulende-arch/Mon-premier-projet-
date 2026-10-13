import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'models.dart';
import 'tips_repository.dart';

/// Pronos publiés par le moteur dans Firestore (voir buteo/engine).
///
/// Les documents du jour sont suivis en direct (scores, résultats). Les
/// rubriques VIP refusées par les règles de sécurité sont marquées
/// verrouillées. Les statistiques viennent du document `stats/summary`.
class FirestoreTipsRepository extends TipsRepository {
  FirestoreTipsRepository({FirebaseFirestore? db, DateTime Function()? clock})
    : _db = db ?? FirebaseFirestore.instance,
      _clock = clock ?? (() => DateTime.now().toUtc());

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  final _days = <String, RubricDay>{};
  final _locked = <String>{};
  final _requested = <String>{};
  final _subs = <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _summarySub;
  Map<String, Map<String, PickStats>> _summary = {};
  List<TeamGroup> _teams = const [];
  bool _disposed = false;

  /// Commence à suivre les statistiques et charge la liste des équipes.
  Future<void> start() async {
    _summarySub = _db.doc('stats/summary').snapshots().listen((snap) {
      _summary = summaryFromDoc(snap.data());
      _changed();
    }, onError: (Object e) => debugPrint('Statistiques : $e'));
    try {
      _teams = teamGroupsFromDoc((await _db.doc('config/teams').get()).data());
      _changed();
    } catch (e) {
      debugPrint('Équipes : $e');
    }
  }

  @override
  bool get isDemo => false;

  @override
  DateTime now() => _clock();

  static String _key(Rubric r, DateTime date) => '${dateKey(date)}_${r.id}';

  @override
  RubricDay day(Rubric rubric, DateTime date) {
    final key = _key(rubric, date);
    if (_requested.add(key)) _load(key, today: dayOf(date) == dayOf(now()));
    return _days[key] ?? const RubricDay();
  }

  @override
  bool isLocked(Rubric rubric, DateTime date) => _locked.contains(_key(rubric, date));

  void _load(String key, {required bool today}) {
    final ref = _db.doc('picks/$key');
    void onDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
      _locked.remove(key);
      _days[key] = rubricDayFromDoc(snap.data());
      _changed();
    }

    void onError(Object e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _locked.add(key);
        _changed();
      } else {
        debugPrint('Pronos $key : $e');
        _requested.remove(key); // nouvel essai au prochain affichage
      }
    }

    if (today) {
      // Le jour même : mises à jour en direct (scores, résultats).
      _subs[key] = ref.snapshots().listen(onDoc, onError: onError);
    } else {
      ref.get().then(onDoc, onError: onError);
    }
  }

  @override
  void refreshAccess() {
    final vip = {for (final r in vipRubrics) r.id};
    for (final key in _requested.toList()) {
      if (vip.contains(key.substring(11))) {
        _subs.remove(key)?.cancel();
        _requested.remove(key);
        _locked.remove(key);
        _days.remove(key);
      }
    }
    _changed();
  }

  @override
  PickStats stats(Rubric rubric, int days) {
    final today = dayOf(now());
    var s = const PickStats();
    for (var d = 1; d <= days; d++) {
      final date = dateKey(today.subtract(Duration(days: d)));
      s = s + (_summary[date]?[rubric.id] ?? const PickStats());
    }
    return s;
  }

  @override
  double? dayRate(DateTime date) {
    final day = _summary[dateKey(date)];
    if (day == null || day.isEmpty) return null;
    return day.values.fold(const PickStats(), (a, b) => a + b).rate;
  }

  @override
  List<TeamGroup> teamGroups() => _teams;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _summarySub?.cancel();
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Lecture des documents écrits par le moteur (format décrit dans engine/picks.py).

Sport _sport(Object? s) => switch (s) {
  'basket' => Sport.basket,
  'tennis' => Sport.tennis,
  _ => Sport.foot,
};

StatusKind _kind(Object? s) => switch (s) {
  'live' => StatusKind.live,
  'won' => StatusKind.won,
  'lost' => StatusKind.lost,
  'void' => StatusKind.voided,
  _ => StatusKind.soon,
};

int? _int(Object? v) => v is num ? v.toInt() : null;

Tip tipFromMap(Map<String, dynamic> m) {
  final kickoff = DateTime.parse(m['kickoff'] as String).toUtc();
  final score = m['score'] is Map ? Map<String, dynamic>.from(m['score'] as Map) : null;
  final half = m['halfTime'] is Map ? Map<String, dynamic>.from(m['halfTime'] as Map) : null;
  final kind = _kind(m['status']);
  final tip = Tip(
    fixture: Fixture(
      league: m['league'] as String? ?? '',
      country: m['country'] as String? ?? '',
      home: m['home'] as String? ?? '',
      away: m['away'] as String? ?? '',
      sport: _sport(m['sport']),
    ),
    market: m['market'] as String? ?? '',
    label: m['label'] as String? ?? '',
    odds: (m['odds'] as num?)?.toDouble() ?? 1,
    time: '${kickoff.hour.toString().padLeft(2, '0')}:${kickoff.minute.toString().padLeft(2, '0')}',
  );
  tip.confidence = _int(m['confidence']) ?? 0;
  tip.won = kind == StatusKind.won;
  if (score != null) {
    tip.score = Score(_int(score['home']) ?? 0, _int(score['away']) ?? 0);
  }
  tip.reported = TipStatus(
    kind,
    label: kind == StatusKind.live ? (m['minute'] as String? ?? 'En cours') : null,
    home: kind == StatusKind.soon || kind == StatusKind.voided ? null : _int(score?['home']),
    away: kind == StatusKind.soon || kind == StatusKind.voided ? null : _int(score?['away']),
  );
  // Le score à la mi-temps sert au libellé « mène à la pause ».
  if (half != null && score != null) {
    tip.score = Score(
      tip.score.home,
      tip.score.away,
      goalsHome: List.filled(_int(half['home']) ?? 0, 45),
      goalsAway: List.filled(_int(half['away']) ?? 0, 45),
    );
  }
  return tip;
}

/// Document `picks/{date}_{rubrique}` → pronos de la journée (vide si absent).
RubricDay rubricDayFromDoc(Map<String, dynamic>? doc) {
  if (doc == null) return const RubricDay();
  final tips = [
    for (final t in (doc['tips'] as List? ?? const []))
      if (t is Map) tipFromMap(Map<String, dynamic>.from(t)),
  ];
  tips.sort((a, b) => a.kickoff.compareTo(b.kickoff));
  if (doc['combo'] == true && tips.isNotEmpty) return RubricDay(combo: Combo(tips));
  return RubricDay(tips: tips);
}

/// Document `stats/summary` → résultats par jour puis par rubrique.
Map<String, Map<String, PickStats>> summaryFromDoc(Map<String, dynamic>? doc) {
  final days = doc?['days'];
  if (days is! Map) return {};
  return {
    for (final e in days.entries)
      if (e.value is Map)
        e.key as String: {
          for (final r in (e.value as Map).entries)
            if (r.value is Map)
              r.key as String: PickStats(
                count: _int((r.value as Map)['count']) ?? 0,
                won: _int((r.value as Map)['won']) ?? 0,
                oddsSum: ((r.value as Map)['oddsSum'] as num?)?.toDouble() ?? 0,
                profit: ((r.value as Map)['profit'] as num?)?.toDouble() ?? 0,
              ),
        },
  };
}

/// Document `config/teams` → championnats et équipes pour les favoris.
List<TeamGroup> teamGroupsFromDoc(Map<String, dynamic>? doc) {
  final groups = doc?['groups'];
  if (groups is! List) return const [];
  return [
    for (final g in groups)
      if (g is Map)
        TeamGroup(
          sport: _sport(g['sport']),
          league: g['league'] as String? ?? '',
          country: g['country'] as String? ?? '',
          teams: [for (final t in (g['teams'] as List? ?? const [])) t as String]..sort(),
        ),
  ];
}
