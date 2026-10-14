import 'package:buteo/data/models.dart';
import 'package:buteo/services/auth_service.dart';
import 'package:buteo/services/notification_service.dart';
import 'package:buteo/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeUserStore store;
  late FakeNotificationService notifier;

  Future<AppState> makeState([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    auth = FakeAuthService();
    store = FakeUserStore();
    notifier = FakeNotificationService();
    final state = AppState(await SharedPreferences.getInstance(), auth: auth, store: store, notifier: notifier);
    await state.start();
    return state;
  }

  /// Laisse passer les événements du compte simulé.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('les équipes suivies restent sur le téléphone sans compte', () async {
    final state = await makeState();
    state.toggleFavorite(Sport.foot, 'ASEC Mimosas');
    expect(state.isFavorite(Sport.foot, 'ASEC Mimosas'), isTrue);
    expect(state.isFavorite(Sport.basket, 'ASEC Mimosas'), isFalse);
    expect(store.docs, isEmpty);

    // Relancer l'app retrouve les favoris.
    final prefs = await SharedPreferences.getInstance();
    final again = AppState(prefs);
    expect(again.isFavorite(Sport.foot, 'ASEC Mimosas'), isTrue);

    state.toggleFavorite(Sport.foot, 'ASEC Mimosas');
    expect(state.favoriteCount, 0);
  });

  test('à la connexion, favoris et alertes du compte sont fusionnés avec le téléphone', () async {
    final state = await makeState();
    state.toggleFavorite(Sport.foot, 'Lyon');
    store.docs['u1'] = {
      'favorites': ['basket:Lakers'],
      'notifications': {Alerts.drop: false, Alerts.results: true, Alerts.live: true},
    };

    await state.signInWithGoogle();
    await flush();
    await flush();

    expect(state.account?.label, 'Awa Koné');
    expect(state.isFavorite(Sport.foot, 'Lyon'), isTrue);
    expect(state.isFavorite(Sport.basket, 'Lakers'), isTrue);
    expect(state.notifications[Alerts.drop], isFalse);
    expect(store.docs['u1']!['favorites'], ['basket:Lakers', 'foot:Lyon']);
    expect(store.docs['u1']!['pushToken'], 'jeton-test');
    expect(notifier.applied.last[Alerts.live], isTrue);
  });

  test('une fois connecté, chaque changement est enregistré avec le compte', () async {
    final state = await makeState();
    await state.signInWithGoogle();
    await flush();

    state.toggleFavorite(Sport.tennis, 'Fils A.');
    state.toggleNotification(Alerts.results);
    await flush();

    expect(store.docs['u1']!['favorites'], ['tennis:Fils A.']);
    expect((store.docs['u1']!['notifications'] as Map)[Alerts.results], isFalse);
  });

  test('connexion par SMS : un mauvais code est refusé, le bon connecte', () async {
    final state = await makeState();
    final step = await state.sendSmsCode('+2250700000000');
    expect(step, isA<SmsCodeSent>());
    final id = (step as SmsCodeSent).verificationId;

    await expectLater(state.confirmSmsCode(id, '000000'), throwsA(isA<AuthFailure>()));
    await state.confirmSmsCode(id, '123456');
    await flush();
    expect(state.account?.label, '+2250700000000');
  });

  test('supprimer le compte efface les données en ligne et déconnecte', () async {
    final state = await makeState();
    await state.signInWithGoogle();
    await flush();
    state.toggleFavorite(Sport.foot, 'Raja');
    await flush();
    expect(store.docs, contains('u1'));

    await state.deleteAccount();
    await flush();
    expect(store.docs, isNot(contains('u1')));
    expect(auth.deleted, isTrue);
    expect(state.signedIn, isFalse);
    // Les favoris restent sur le téléphone.
    expect(state.isFavorite(Sport.foot, 'Raja'), isTrue);
  });

  test("l'autorisation des notifications n'est demandée qu'une fois", () async {
    final state = await makeState();
    await state.askNotificationPermissionOnce();
    await state.askNotificationPermissionOnce();
    expect(notifier.permissionRequests, 1);
    expect(notifier.applied.last[Alerts.drop], isTrue);
  });

  test('sans Firebase, la connexion explique pourquoi elle est indisponible', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    expect(state.auth.available, isFalse);
    await expectLater(
      state.signInWithGoogle(),
      throwsA(isA<AuthFailure>().having((e) => e.message, 'message', notConfiguredMessage)),
    );
  });

  test('un achat fait sur le site apparaît au retour dans l’app', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = FakeAuthService();
    final store = FakeUserStore();
    final state = AppState(await SharedPreferences.getInstance(), auth: auth, store: store, demoMode: false);
    await state.start();
    await state.signInWithGoogle();
    await flush();
    var refreshed = 0;
    state.onAccessChanged = () => refreshed++;

    // Rien de nouveau : pas de rechargement inutile des pronos.
    await state.refreshAccess();
    expect(refreshed, 0);

    store.docs['u1'] = {
      'tier': 'elite',
      'tierUntil': DateTime.now().toUtc().add(const Duration(days: 30)),
      'coupons': <String>[],
    };
    await state.refreshAccess();
    expect(state.tier, Tier.elite);
    expect(refreshed, 1);
    await state.refreshAccess();
    expect(refreshed, 1);
  });

  group('achats Google Play (vraies données)', () {
    Future<(AppState, FakeBillingService)> realState() async {
      SharedPreferences.setMockInitialValues({});
      final billing = FakeBillingService();
      final state = AppState(await SharedPreferences.getInstance(), demoMode: false, billing: billing);
      await state.start();
      return (state, billing);
    }

    test('un abonnement confirmé donne la formule et prévient l’utilisateur', () async {
      final (state, billing) = await realState();
      final messages = <String>[];
      state.notices.listen(messages.add);
      var refreshed = 0;
      state.onAccessChanged = () => refreshed++;

      await state.buySubscription(Tier.elite, 3);
      await flush();
      expect(billing.bought, ['buteo_elite/trimestriel']);
      expect(state.tier, Tier.elite);
      expect(refreshed, 1);
      expect(messages, ['Bienvenue dans la formule Élite']);
    });

    test('une formule échue ne compte plus', () async {
      final (state, _) = await realState();
      state.serverTier = Tier.pro;
      state.serverTierUntil = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      expect(state.tier, Tier.free);
      state.serverTierUntil = DateTime.now().toUtc().add(const Duration(days: 1));
      expect(state.tier, Tier.pro);
    });

    test('paiement en attente : un message, aucun accès', () async {
      final (state, billing) = await realState();
      final messages = <String>[];
      state.notices.listen(messages.add);
      billing.pending();
      await flush();
      expect(messages.single, contains('en attente'));
      expect(state.tier, Tier.free);
    });

    test('les prix locaux de Google Play sont chargés au démarrage', () async {
      final (state, _) = await realState();
      expect(state.playPrices['coupon_vip'], '500 FCFA');
    });
  });
}
