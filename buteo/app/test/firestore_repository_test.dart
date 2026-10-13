import 'dart:convert';
import 'dart:io';

import 'package:buteo/data/catalog.dart';
import 'package:buteo/data/firestore_repository.dart';
import 'package:buteo/data/models.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/state/app_state.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Documents produits par le moteur Python (`python -m engine essai --json …`) :
/// c'est le contrat entre le moteur et l'application.
Map<String, Map<String, dynamic>> engineExample() {
  final raw = jsonDecode(File('../engine/exemple_picks.json').readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
}

void main() {
  group('lecture des documents du moteur', () {
    final docs = engineExample();

    test('chaque rubrique du moteur se lit sans erreur', () {
      expect(docs, hasLength(10));
      for (final doc in docs.values) {
        final rubric = rubricsById[doc['rubric']]!;
        final day = rubricDayFromDoc(doc);
        expect(day.allTips, hasLength((doc['tips'] as List).length), reason: rubric.id);
        expect(day.isCombo, doc['combo'] == true);
        for (final t in day.allTips) {
          expect(t.label, isNotEmpty);
          expect(t.odds, greaterThan(1));
          expect(t.confidence, inInclusiveRange(1, 99));
          expect(t.time, matches(RegExp(r'^\d\d:\d\d$')));
          expect(t.reported?.kind, anyOf(StatusKind.won, StatusKind.lost));
          expect(t.reported!.hasScore, isTrue);
        }
      }
    });

    test('états envoyés par le moteur : en cours, à venir, annulé', () {
      final base = Map<String, dynamic>.from((docs.values.first['tips'] as List).first as Map);
      final live = tipFromMap({
        ...base,
        'status': 'live',
        'minute': "63'",
        'score': {'home': 1, 'away': 0},
      });
      expect(statusOf(live, DateTime.utc(2026), DateTime.utc(2026)).label, "63'");
      expect(live.reported!.home, 1);

      final soon = tipFromMap({...base, 'status': 'soon'}..remove('score'));
      expect(soon.reported!.kind, StatusKind.soon);
      expect(soon.reported!.hasScore, isFalse);

      final cancelled = tipFromMap({...base, 'status': 'void'});
      expect(cancelled.reported!.kind, StatusKind.voided);
    });

    test('un match annulé dans un combiné compte comme gagné à la cote 1', () {
      final combo = docs.values.firstWhere((d) => d['combo'] == true);
      final tips = [
        for (final (i, t) in (combo['tips'] as List).indexed)
          {...Map<String, dynamic>.from(t as Map), 'status': i == 0 ? 'void' : 'won'},
      ];
      final day = rubricDayFromDoc({...combo, 'tips': tips});
      expect(comboStatus(day.combo!, DateTime.utc(2026), DateTime.utc(2026)).kind, StatusKind.won);
    });

    test('document absent : aucun prono', () {
      expect(rubricDayFromDoc(null).picks, isEmpty);
    });
  });

  group('source Firestore', () {
    final now = DateTime.utc(2026, 10, 14, 20, 0);
    late FakeFirebaseFirestore db;
    late FirestoreTipsRepository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      for (final e in engineExample().entries) {
        await db.doc(e.key).set(e.value);
      }
      await db.doc('stats/summary').set({
        'days': {
          '2026-10-13': {
            'selection': {'count': 3, 'won': 2, 'oddsSum': 4.2, 'profit': 0.3},
            'c10': {'count': 1, 'won': 0, 'oddsSum': 14.0, 'profit': -1.0},
          },
          '2026-09-01': {
            'selection': {'count': 3, 'won': 3, 'oddsSum': 4.0, 'profit': 1.0},
          },
        },
      });
      await db.doc('config/teams').set({
        'groups': [
          {
            'sport': 'foot',
            'league': 'Ligue 1',
            'country': "Côte d'Ivoire",
            'teams': ['SOA', 'ASEC Mimosas'],
          },
        ],
      });
      repo = FirestoreTipsRepository(db: db, clock: () => now);
      await repo.start();
    });

    tearDown(() => repo.dispose());

    test('les pronos du jour arrivent après chargement', () async {
      final selection = rubricsById['selection']!;
      expect(repo.day(selection, now).picks, isEmpty); // pas encore chargé
      await pumpEventQueue();
      expect(repo.day(selection, now).tips, isNotEmpty);
      expect(repo.isDemo, isFalse);
    });

    test('statistiques des 7 et 30 derniers jours d’après le résumé', () async {
      await pumpEventQueue();
      final s7 = repo.stats(rubricsById['selection']!, 7);
      expect((s7.count, s7.won), (3, 2));
      expect(repo.stats(rubricsById['selection']!, 60).count, 6);
      expect(repo.dayRate(DateTime.utc(2026, 10, 13)), 0.5);
      expect(repo.dayRate(DateTime.utc(2026, 10, 12)), isNull);
    });

    test('équipes pour les favoris', () async {
      await pumpEventQueue();
      final groups = repo.teamGroups();
      expect(groups.single.teams, ['ASEC Mimosas', 'SOA']);
    });

    test('mise à jour en direct du document du jour', () async {
      final selection = rubricsById['selection']!;
      repo.day(selection, now);
      await pumpEventQueue();
      final ref = db.doc('picks/2026-10-14_selection');
      final doc = (await ref.get()).data()!;
      final tips = [
        for (final t in doc['tips'] as List)
          {...Map<String, dynamic>.from(t as Map), 'status': 'live', 'minute': "12'"},
      ];
      await ref.update({'tips': tips});
      await pumpEventQueue();
      expect(statusOf(repo.day(selection, now).tips.first, now, now).label, "12'");
    });
  });

  group('accès avec les vraies données', () {
    Future<AppState> makeState(Map<String, dynamic> remote) async {
      SharedPreferences.setMockInitialValues({'tier': 'elite'}); // formule de démonstration ignorée
      final store = FakeUserStore()..docs['u1'] = remote;
      final state = AppState(
        await SharedPreferences.getInstance(),
        auth: FakeAuthService(),
        store: store,
        demoMode: false,
      );
      await state.start();
      return state;
    }

    test('sans compte : rubriques VIP fermées, même avec une formule de démonstration enregistrée', () async {
      final state = await makeState({});
      final day = DateTime.utc(2026, 10, 14);
      expect(state.tier, Tier.free);
      expect(state.canSee(rubricsById['c10']!, day), isFalse);
      expect(state.canSee(rubricsById['selection']!, day), isTrue);
    });

    test('la formule et les coupons viennent du profil écrit par le serveur', () async {
      final state = await makeState({
        'tier': 'pro',
        'coupons': ['2026-10-14|score'],
      });
      var accessChanges = 0;
      state.onAccessChanged = () => accessChanges++;
      await state.signInWithGoogle();
      await pumpEventQueue();

      final day = DateTime.utc(2026, 10, 14);
      expect(state.tier, Tier.pro);
      expect(state.canSee(rubricsById['c10']!, day), isTrue);
      expect(state.canSee(rubricsById['score']!, day), isTrue); // coupon du jour
      expect(state.canSee(rubricsById['score']!, DateTime.utc(2026, 10, 15)), isFalse);
      expect(state.canSee(rubricsById['c5']!, day), isFalse);
      expect(accessChanges, greaterThan(0));

      await state.signOut();
      await pumpEventQueue();
      expect(state.tier, Tier.free);
    });
  });
}
