import 'package:buteo/data/catalog.dart';
import 'package:buteo/data/models.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13, 20, 10);
  final today = dayOf(now);
  final repo = DemoTipsRepository(clock: () => now);

  group('hasard reproductible', () {
    test('donne les mêmes tirages que la maquette JavaScript', () {
      final r = Rng(12345);
      expect([r.next(), r.next(), r.next()].map((x) => x.toStringAsFixed(15)), [
        '0.979728267760947',
        '0.306752264499664',
        '0.484205421525985',
      ]);
      final big = Rng(4294967295 + 7919 * 3);
      expect([big.next(), big.next()].map((x) => x.toStringAsFixed(15)), ['0.150135750649497', '0.474167805397883']);
      expect(fnv1a('selection|2026-10-13'), 1591593452);
      expect(fnv1a('c5|2026-10-13'), 1199443708);
    });

    test('une même rubrique et une même date donnent les mêmes pronos', () {
      final a = DemoTipsRepository(clock: () => now).day(rubricsById['selection']!, today);
      final b = DemoTipsRepository(clock: () => now).day(rubricsById['selection']!, today);
      expect(
        a.tips.map((t) => '${t.fixture.home}-${t.fixture.away}-${t.odds}'),
        b.tips.map((t) => '${t.fixture.home}-${t.fixture.away}-${t.odds}'),
      );
    });
  });

  group('pronos générés', () {
    test('chaque rubrique publie le bon nombre de pronos', () {
      for (final r in rubrics) {
        final day = repo.day(r, today);
        if (r.isCombo) {
          expect(day.combo!.legs, hasLength(r.comboLegs), reason: r.id);
        } else {
          expect(day.tips, hasLength(r.count), reason: r.id);
        }
      }
    });

    test('les combinés atteignent leur cote minimale', () {
      for (final id in ['c5', 'c10']) {
        final r = rubricsById[id]!;
        for (var d = 0; d < 60; d++) {
          final combo = repo.day(r, today.subtract(Duration(days: d))).combo!;
          expect(combo.odds, greaterThanOrEqualTo(r.comboMin), reason: '$id, J-$d');
        }
      }
    });

    test('le résultat respecte la règle du marché', () {
      for (final r in rubrics) {
        for (var d = 1; d <= 30; d++) {
          for (final t in repo.day(r, today.subtract(Duration(days: d))).allTips) {
            expect(markets[t.market]!.check(t.score, t.fixture), t.won, reason: '${r.id} ${t.label}');
            expect(t.confidence, inInclusiveRange(8, 93));
          }
        }
      }
    });
  });

  group('état des matchs', () {
    final tip =
        Tip(
            fixture: const Fixture(league: 'Ligue 1', country: 'France', home: 'Lyon', away: 'Nice', sport: Sport.foot),
            market: 'o15',
            label: 'Plus de 1,5 buts',
            odds: 1.3,
            time: '19:00',
          )
          ..score = const Score(2, 1, goalsHome: [10, 70], goalsAway: [50])
          ..won = true;

    test('à venir avant le coup d\'envoi', () {
      expect(statusOf(tip, today, DateTime.utc(2026, 10, 13, 18, 59)).kind, StatusKind.soon);
    });

    test('en direct avec le score à la minute près', () {
      final s = statusOf(tip, today, DateTime.utc(2026, 10, 13, 19, 30));
      expect(s.kind, StatusKind.live);
      expect(s.label, "30'");
      expect((s.home, s.away), (1, 0));
      expect(statusOf(tip, today, DateTime.utc(2026, 10, 13, 19, 50)).label, 'MT');
    });

    test('gagné une fois le match terminé, et pour les jours passés', () {
      expect(statusOf(tip, today, DateTime.utc(2026, 10, 13, 21, 0)).kind, StatusKind.won);
      expect(statusOf(tip, today.subtract(const Duration(days: 1)), now).kind, StatusKind.won);
    });
  });

  test('statistiques : réussite et rendement à mise fixe', () {
    final s = PickStats.of([_P(2.0, true), _P(1.5, false), _P(1.5, false), _P(3.0, true)]);
    expect(s.count, 4);
    expect(s.rate, .5);
    expect(s.roi, closeTo((1 + 2 - 1 - 1) / 4, 1e-9));
    expect(percent(s.roi, signed: true), '+25 %');
  });

  test('formats français', () {
    expect(odds(1.5), '1,50');
    expect(fcfa(13900), '13 900 FCFA');
    expect(longDate(today), 'Mardi 13 octobre');
    expect(shortDate(today), 'Mar. 13 oct.');
    expect(percent(.742), '74,2 %');
    expect(percent(-1, signed: true), '−100 %');
    expect(hoursMinutes(230), '3 h 50');
  });
}

class _P implements Pick {
  _P(this.odds, this.won);

  @override
  final double odds;
  @override
  final bool won;
  @override
  int get confidence => 50;
}
