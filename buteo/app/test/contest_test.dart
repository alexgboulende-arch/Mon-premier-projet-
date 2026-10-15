import 'package:buteo/app.dart';
import 'package:buteo/data/contest.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

final _now = DateTime.utc(2026, 10, 13, 20, 10);

ContestMatch _match(int id, String home, String away, int hour, {String? result, ({int home, int away})? score}) =>
    ContestMatch(
      fixtureId: id,
      league: 'Ligue Europa',
      country: 'Europe',
      home: home,
      away: away,
      kickoff: DateTime.utc(2026, 10, 13, hour),
      odds: const {'1': 1.85, 'X': 3.4, '2': 4.2},
      result: result,
      score: score,
    );

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  test('semaine et mois comme le moteur (semaines ISO)', () {
    expect(weekId(DateTime.utc(2026, 10, 14)), '2026-W42');
    expect(weekId(DateTime.utc(2026, 10, 12)), '2026-W42');
    expect(weekId(DateTime.utc(2027, 1, 1)), '2026-W53');
    expect(weekId(DateTime.utc(2026, 1, 1)), '2026-W01');
    expect(monthId(DateTime.utc(2026, 10, 14)), '2026-10');
  });

  test('pseudos acceptés par les règles', () {
    expect(validPseudo('Awa Koné'), isTrue);
    expect(validPseudo('lion_241'), isTrue);
    expect(validPseudo('A'), isFalse);
    expect(validPseudo('www.paris<script>'), isFalse);
    expect(validPseudo('x' * 21), isFalse);
  });

  test('lecture d’un match du concours publié par le moteur', () {
    final m = ContestMatch.fromMap({
      'fixtureId': 1636222,
      'league': 'Ligue Europa',
      'country': 'Europe',
      'home': 'Benfica',
      'away': 'Celtic',
      'kickoff': '2026-10-15T19:00:00Z',
      'odds': {'1': 1.25, 'X': 6.0, '2': 11.0},
      'result': '1',
      'score': {'home': 2, 'away': 0},
    });
    expect(m.kickoff, DateTime.utc(2026, 10, 15, 19));
    expect(m.pointsFor('1'), 13);
    expect(m.score, (home: 2, away: 0));
    expect(m.isOpen(DateTime.utc(2026, 10, 15, 18, 59)), isTrue);
    expect(m.isOpen(DateTime.utc(2026, 10, 15, 19)), isFalse);
  });

  testWidgets('jouer au concours : pseudo, choix avant le coup d’envoi, classement', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = FakeUserStore();
    final state = AppState(await SharedPreferences.getInstance(), auth: FakeAuthService(), store: store);
    await state.start();
    await state.signInWithGoogle();
    final contest = MemoryContestRepository(
      contest: ContestDay(
        date: '2026-10-13',
        matches: [
          _match(1, 'Benfica', 'Celtic', 19, result: '1', score: (home: 2, away: 0)),
          _match(2, 'Lyon', 'Rangers', 21),
        ],
      ),
      week: const [
        LeaderRow(uid: 'k', pseudo: 'Kofi', points: 120, correct: 6, played: 10, rank: 1),
        LeaderRow(uid: 'u1', pseudo: 'Lion de Libreville', points: 37, correct: 2, played: 5, rank: 2),
      ],
      clock: () => _now,
    );
    await tester.pumpWidget(
      ButeoApp(
        state: state,
        repository: DemoTipsRepository(clock: () => _now),
        contest: contest,
        splashDuration: const Duration(milliseconds: 10),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Jouer'), 200);
    await tester.ensureVisible(find.text('Jouer'));
    await settle(tester);
    await tester.tap(find.text('Jouer'));
    await settle(tester);
    expect(find.text('Choisis ton pseudo'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A');
    await tester.tap(find.text('Valider'));
    await settle(tester);
    expect(find.textContaining('3 à 20 caractères'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Lion de Libreville');
    await tester.tap(find.text('Valider'));
    await settle(tester);
    expect(state.pseudo, 'Lion de Libreville');
    expect(store.docs['u1']!['pseudo'], 'Lion de Libreville');

    // Match terminé : fermé, score affiché. Match à venir : on peut jouer « 1 ».
    expect(find.text('2-0'), findsOneWidget);
    expect(find.text('Terminé'), findsOneWidget);
    final open = find.bySemanticsLabel(RegExp(r'^1, cote 1\.85')).last;
    await tester.ensureVisible(open);
    await tester.tap(open);
    await settle(tester);
    expect(contest.picks['2026-10-13|u1'], {2: '1'});

    final closed = find.bySemanticsLabel(RegExp(r'^2, cote 4\.20')).first;
    await tester.ensureVisible(closed);
    await tester.tap(closed);
    await settle(tester);
    expect(contest.picks['2026-10-13|u1'], {2: '1'});

    await tester.scrollUntilVisible(find.text('Lion de Libreville (toi)'), 200);
    expect(find.text('Lion de Libreville (toi)'), findsOneWidget);
    expect(find.text('Kofi'), findsOneWidget);
  });
}
