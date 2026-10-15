// Captures d'écran de la fiche Play Store (1080 × 1920), avec les vraies polices.
//
//   BUTEO_CAPTURES=1 flutter test test/captures_test.dart --update-goldens
//
// Les images sont écrites dans buteo/store/captures/. Sans BUTEO_CAPTURES, ce
// fichier est ignoré (les images ne servent pas de référence aux tests).
import 'dart:io';

import 'package:buteo/app.dart';
import 'package:buteo/data/catalog.dart';
import 'package:buteo/data/contest.dart';
import 'package:buteo/data/journal.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/state/app_state.dart';
import 'package:buteo/ui/screens/contest_screen.dart';
import 'package:buteo/ui/screens/journal_screen.dart';
import 'package:buteo/ui/screens/rubric_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

final _captures = Platform.environment['BUTEO_CAPTURES'] == '1';
final _now = DateTime.utc(2026, 10, 13, 20, 10);

/// Pronos simulés, sans le bandeau « démonstration ».
class _StoreRepository extends DemoTipsRepository {
  _StoreRepository() : super(clock: () => _now);

  @override
  bool get isDemo => false;
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }

  await family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Inter-$w.otf',
  ]);
  await family('BarlowCondensed', [
    'assets/fonts/BarlowCondensed-SemiBold.ttf',
    'assets/fonts/BarlowCondensed-Bold.ttf',
  ]);
  final flutter = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await family('MaterialIcons', ['$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void main() {
  late AppState state;
  late MemoryContestRepository contest;

  Future<void> start(WidgetTester tester) async {
    // Vraie lecture de fichiers : hors du temps simulé des tests.
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'pseudo': 'Lion de Libreville'});
    state = AppState(await SharedPreferences.getInstance(), auth: FakeAuthService(), demoMode: false);
    await state.start();
    await state.signInWithGoogle();
    final repo = _StoreRepository();
    ContestMatch match(
      int id,
      String league,
      String country,
      String home,
      String away,
      int hour,
      int minute,
      List<double> odds,
    ) => ContestMatch(
      fixtureId: id,
      league: league,
      country: country,
      home: home,
      away: away,
      kickoff: DateTime.utc(2026, 10, 13, hour, minute),
      odds: {'1': odds[0], 'X': odds[1], '2': odds[2]},
    );
    contest = MemoryContestRepository.demo(repo)
      ..contest = ContestDay(
        date: '2026-10-13',
        matches: [
          match(1, 'Ligue des champions', 'Europe', 'PSG', 'Bayern Munich', 20, 45, [2.35, 3.60, 2.90]),
          match(2, 'Ligue 1', 'Côte d’Ivoire', 'ASEC Mimosas', 'Africa Sports', 21, 0, [1.72, 3.30, 4.60]),
          match(3, 'Ligue des champions', 'Europe', 'Real Madrid', 'Arsenal', 21, 0, [1.95, 3.70, 3.60]),
          match(4, 'Botola Pro', 'Maroc', 'Wydad', 'Raja', 21, 30, [2.40, 2.95, 3.10]),
          match(5, 'Ligue des champions CAF', 'Afrique', 'Al Ahly', 'Espérance', 22, 0, [1.65, 3.40, 5.20]),
        ],
      )
      ..picks['2026-10-13|u1'] = {1: '1', 2: '1', 3: 'X'}
      ..profile = const PlayerProfile(
        pseudo: 'Lion de Libreville',
        week: (period: '2026-W42', points: 87, rank: 4, correct: 6, played: 10),
        month: (period: '2026-10', points: 312, rank: 9, correct: 21, played: 40),
        perfectDays: 1,
        podiums: 2,
      );
    contest.week = [
      ...contest.week.take(3),
      const LeaderRow(uid: 'u1', pseudo: 'Lion de Libreville', points: 87, correct: 6, played: 10, rank: 4),
      ...contest.week
          .skip(3)
          .map(
            (r) => LeaderRow(
              uid: r.uid,
              pseudo: r.pseudo,
              points: r.points - 40,
              correct: r.correct,
              played: r.played,
              rank: r.rank + 1,
            ),
          ),
    ];
    await tester.pumpWidget(
      ButeoApp(state: state, repository: repo, contest: contest, splashDuration: const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> push(WidgetTester tester, Widget screen) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => screen));
    await settle(tester);
  }

  Future<void> capture(String name) =>
      expectLater(find.byType(MaterialApp), matchesGoldenFile('../../store/captures/$name.png'));

  testWidgets('captures de la fiche Play Store', skip: !_captures, (tester) async {
    await start(tester);
    await capture('1-accueil');

    await push(tester, RubricScreen(rubric: rubricsById['selection']!));
    await capture('2-selection-du-jour');
    Navigator.of(tester.element(find.byType(RubricScreen))).pop();
    await settle(tester);

    await push(tester, const ContestScreen());
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await settle(tester);
    await capture('3-concours');
    Navigator.of(tester.element(find.byType(ContestScreen))).pop();
    await settle(tester);

    state.setTab(2);
    await settle(tester);
    await capture('4-statistiques');

    state.setTab(3);
    await settle(tester);
    await capture('5-offres');

    for (final (label, odds, stake, status, day) in [
      ('Benfica – Celtic · Victoire Benfica', 1.25, 5000, BetStatus.won, 10),
      ('Lyon – Rangers · Plus de 2,5 buts', 1.90, 2000, BetStatus.won, 11),
      ('Roma – Real Madrid · Moins de 3,5 buts', 1.77, 2000, BetStatus.lost, 12),
      ('Combiné du jour · 3 matchs', 2.85, 1000, BetStatus.pending, 13),
    ]) {
      final e = await state.journal.add(label: label, odds: odds, stake: stake, day: DateTime.utc(2026, 10, day));
      await state.journal.update(e.copyWith(status: status));
    }
    state.setTab(0);
    await settle(tester);
    await push(tester, const JournalScreen());
    await capture('6-journal');
  });
}
