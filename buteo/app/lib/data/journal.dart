import 'package:cloud_firestore/cloud_firestore.dart';

/// Journal de paris : les paris de l'utilisateur, ses gains et ses pertes.
enum BetStatus {
  pending('En cours'),
  won('Gagné'),
  lost('Perdu'),
  refunded('Remboursé');

  const BetStatus(this.label);
  final String label;
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.day,
    required this.label,
    required this.odds,
    required this.stake,
    this.status = BetStatus.pending,
    required this.updatedAt,
  });

  final String id;
  final DateTime day;
  final String label;
  final double odds;

  /// Mise en FCFA.
  final int stake;
  final BetStatus status;
  final DateTime updatedAt;

  bool get settled => status == BetStatus.won || status == BetStatus.lost;

  /// Gain net : (cote − 1) × mise si gagné, − mise si perdu, 0 sinon.
  int get profit => switch (status) {
    BetStatus.won => (stake * (odds - 1)).round(),
    BetStatus.lost => -stake,
    _ => 0,
  };

  JournalEntry copyWith({
    String? label,
    double? odds,
    int? stake,
    BetStatus? status,
    DateTime? day,
    DateTime? updatedAt,
  }) => JournalEntry(
    id: id,
    day: day ?? this.day,
    label: label ?? this.label,
    odds: odds ?? this.odds,
    stake: stake ?? this.stake,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'day': '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'label': label,
    'odds': odds,
    'stake': stake,
    'status': status.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static JournalEntry? fromMap(Map<String, dynamic> m) {
    try {
      final day = DateTime.parse(m['day'] as String);
      final updated = m['updatedAt'];
      return JournalEntry(
        id: m['id'] as String,
        day: DateTime.utc(day.year, day.month, day.day),
        label: m['label'] as String,
        odds: (m['odds'] as num).toDouble(),
        stake: (m['stake'] as num).toInt(),
        status: BetStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => BetStatus.pending),
        updatedAt: updated is Timestamp ? updated.toDate().toUtc() : DateTime.parse(updated as String).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Bilan d'une liste de paris (seuls les paris gagnés ou perdus comptent).
class JournalStats {
  JournalStats(Iterable<JournalEntry> entries) {
    for (final e in entries) {
      count++;
      if (e.status == BetStatus.pending) pending++;
      if (!e.settled) continue;
      settled++;
      staked += e.stake;
      profit += e.profit;
      if (e.status == BetStatus.won) won++;
    }
  }

  int count = 0;
  int pending = 0;
  int settled = 0;
  int won = 0;
  int staked = 0;
  int profit = 0;

  /// Rendement : bénéfice ÷ mises (null sans pari terminé).
  double? get roi => staked == 0 ? null : profit / staked;
  double? get successRate => settled == 0 ? null : won / settled;
}

/// Copie du journal dans le compte (`users/{uid}/journal/{id}`), pour le retrouver sur un autre téléphone.
abstract class JournalRemote {
  Future<List<Map<String, dynamic>>> load(String uid);
  Future<void> save(String uid, JournalEntry entry);
  Future<void> delete(String uid, String id);
  Future<void> deleteAll(String uid);
}

class NoJournalRemote implements JournalRemote {
  const NoJournalRemote();

  @override
  Future<List<Map<String, dynamic>>> load(String uid) async => const [];

  @override
  Future<void> save(String uid, JournalEntry entry) async {}

  @override
  Future<void> delete(String uid, String id) async {}

  @override
  Future<void> deleteAll(String uid) async {}
}

class FirestoreJournalRemote implements JournalRemote {
  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('journal');

  @override
  Future<List<Map<String, dynamic>>> load(String uid) async => [for (final d in (await _col(uid).get()).docs) d.data()];

  @override
  Future<void> save(String uid, JournalEntry entry) => _col(uid).doc(entry.id).set(entry.toMap());

  @override
  Future<void> delete(String uid, String id) => _col(uid).doc(id).delete();

  @override
  Future<void> deleteAll(String uid) async {
    for (final d in (await _col(uid).get()).docs) {
      await d.reference.delete();
    }
  }
}
