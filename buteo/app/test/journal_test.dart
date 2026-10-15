import 'package:buteo/app.dart';
import 'package:buteo/data/journal.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/state/app_state.dart';
import 'package:buteo/state/journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Copie en ligne simulée.
class FakeJournalRemote implements JournalRemote {
  final docs = <String, Map<String, Map<String, dynamic>>>{};

  @override
  Future<List<Map<String, dynamic>>> load(String uid) async => [...?docs[uid]?.values];

  @override
  Future<void> save(String uid, JournalEntry entry) async => (docs[uid] ??= {})[entry.id] = entry.toMap();

  @override
  Future<void> delete(String uid, String id) async => docs[uid]?.remove(id);

  @override
  Future<void> deleteAll(String uid) async => docs.remove(uid);
}

final _now = DateTime.utc(2026, 10, 13, 20, 10);

JournalEntry _bet(String id, double odds, int stake, BetStatus status, {DateTime? updated}) => JournalEntry(
  id: id,
  day: DateTime.utc(2026, 10, 13),
  label: 'Pari $id',
  odds: odds,
  stake: stake,
  status: status,
  updatedAt: updated ?? _now,
);

void main() {
  test('gains, pertes, rendement et réussite', () {
    final stats = JournalStats([
      _bet('a', 1.85, 2000, BetStatus.won), // +1 700
      _bet('b', 2.10, 1000, BetStatus.lost), // −1 000
      _bet('c', 1.50, 5000, BetStatus.refunded), // ne compte pas
      _bet('d', 3.00, 500, BetStatus.pending), // ne compte pas
    ]);
    expect(stats.count, 4);
    expect(stats.pending, 1);
    expect(stats.settled, 2);
    expect(stats.staked, 3000);
    expect(stats.profit, 700);
    expect(stats.roi, closeTo(700 / 3000, 1e-9));
    expect(stats.successRate, .5);
    expect(JournalStats(const []).roi, isNull);
  });

  test('le journal reste sur le téléphone et se fusionne avec le compte', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final remote = FakeJournalRemote();
    final journal = Journal(prefs, remote: remote, clock: () => _now);

    final first = await journal.add(label: 'Benfica – Celtic · Victoire Benfica', odds: 1.25, stake: 2000);
    await journal.update(first.copyWith(status: BetStatus.won));
    expect(Journal(prefs).entries.single.status, BetStatus.won, reason: 'gardé après redémarrage');
    expect(remote.docs, isEmpty, reason: 'rien en ligne sans compte');

    // Sur un autre téléphone, un pari plus ancien et une version plus récente du premier.
    remote.docs['u1'] = {
      'old': _bet('old', 2.0, 1000, BetStatus.lost).toMap(),
      first.id: first.copyWith(status: BetStatus.refunded, updatedAt: _now.add(const Duration(hours: 1))).toMap(),
    };
    await journal.attach('u1');
    expect(journal.entries.length, 2);
    expect(journal.entries.firstWhere((e) => e.id == first.id).status, BetStatus.refunded);

    final third = await journal.add(label: 'Lyon – Rangers · Plus de 2,5 buts', odds: 1.9, stake: 500);
    expect(remote.docs['u1']!.containsKey(third.id), isTrue);
    await journal.remove(third.id);
    expect(remote.docs['u1']!.containsKey(third.id), isFalse);

    await journal.deleteRemote('u1');
    expect(remote.docs.containsKey('u1'), isFalse);
    expect(journal.entries.length, 2, reason: 'le téléphone garde le journal');
  });

  testWidgets('noter un pari depuis un prono et voir le bilan', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance(), auth: FakeAuthService());
    await tester.pumpWidget(
      ButeoApp(
        state: state,
        repository: DemoTipsRepository(clock: () => _now),
        splashDuration: const Duration(milliseconds: 10),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(seconds: 1));

    // Bouton « Ajouter au journal » du prono phare : pari prérempli.
    await tester.scrollUntilVisible(find.byTooltip('Ajouter au journal'), 200);
    final add = find.byTooltip('Ajouter au journal').first;
    await tester.ensureVisible(add);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(add);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nouveau pari'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Mise'), '2000');
    for (final label in ['Gagné', 'Enregistrer']) {
      await tester.ensureVisible(find.text(label));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 400));
    }

    final entry = state.journal.entries.single;
    expect(entry.stake, 2000);
    expect(entry.status, BetStatus.won);
    expect(entry.label, contains(' · '));
    expect(state.journal.stats.profit, (2000 * (entry.odds - 1)).round());

    // Le journal s'ouvre depuis le profil avec le bilan.
    state.setTab(4);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('Journal de paris'), 200);
    await tester.tap(find.text('Journal de paris'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Bénéfice'), findsOneWidget);
    expect(find.text('Gagné'), findsOneWidget);
    expect(find.textContaining('1 pari terminé'), findsOneWidget);
  });
}
