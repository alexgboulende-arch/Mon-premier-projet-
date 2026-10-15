import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/journal.dart';

/// Journal de paris : gardé sur le téléphone, copié dans le compte quand on est connecté.
class Journal extends ChangeNotifier {
  Journal(this._prefs, {this.remote = const NoJournalRemote(), DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc()) {
    for (final raw in _prefs.getStringList(_kJournal) ?? const <String>[]) {
      final e = JournalEntry.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (e != null) _entries[e.id] = e;
    }
  }

  static const _kJournal = 'journal';

  final SharedPreferences _prefs;
  final JournalRemote remote;
  final DateTime Function() _clock;
  final _entries = <String, JournalEntry>{};
  final _random = Random();
  String? _uid;

  /// Du plus récent au plus ancien.
  List<JournalEntry> get entries => _entries.values.toList()
    ..sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : b.updatedAt.compareTo(a.updatedAt);
    });

  JournalStats get stats => JournalStats(_entries.values);

  Future<JournalEntry> add({required String label, required double odds, required int stake, DateTime? day}) async {
    final now = _clock();
    final entry = JournalEntry(
      id: '${now.millisecondsSinceEpoch}${_random.nextInt(1 << 20).toRadixString(36)}',
      day: day ?? DateTime.utc(now.year, now.month, now.day),
      label: label.trim(),
      odds: odds,
      stake: stake,
      updatedAt: now,
    );
    await _put(entry);
    return entry;
  }

  Future<void> update(JournalEntry entry) => _put(entry.copyWith(updatedAt: _clock()));

  Future<void> remove(String id) async {
    _entries.remove(id);
    await _persist();
    final uid = _uid;
    if (uid != null) await _quietly(() => remote.delete(uid, id));
  }

  Future<void> _put(JournalEntry entry) async {
    _entries[entry.id] = entry;
    await _persist();
    final uid = _uid;
    if (uid != null) await _quietly(() => remote.save(uid, entry));
  }

  Future<void> _persist() async {
    notifyListeners();
    await _prefs.setStringList(_kJournal, [for (final e in _entries.values) jsonEncode(e.toMap())]);
  }

  /// Connexion : on fusionne le téléphone et le compte (la version la plus récente de chaque pari gagne).
  Future<void> attach(String uid) async {
    _uid = uid;
    try {
      final online = <String, JournalEntry>{};
      for (final m in await remote.load(uid)) {
        final e = JournalEntry.fromMap(m);
        if (e != null) online[e.id] = e;
      }
      for (final e in online.values) {
        final local = _entries[e.id];
        if (local == null || e.updatedAt.isAfter(local.updatedAt)) _entries[e.id] = e;
      }
      await _persist();
      for (final e in _entries.values) {
        final copy = online[e.id];
        if (copy == null || e.updatedAt.isAfter(copy.updatedAt)) await remote.save(uid, e);
      }
    } catch (e) {
      debugPrint('Synchronisation du journal : $e');
    }
  }

  void detach() => _uid = null;

  /// Suppression du compte : la copie en ligne disparaît, le téléphone garde le journal.
  Future<void> deleteRemote(String uid) => _quietly(() => remote.deleteAll(uid));

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Journal en ligne : $e');
    }
  }
}
