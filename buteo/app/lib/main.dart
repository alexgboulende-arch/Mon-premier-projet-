import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/contest.dart';
import 'data/journal.dart';
import 'data/firestore_repository.dart';
import 'data/tips_repository.dart';
import 'services/ads_service.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/firebase_config.dart';
import 'services/notification_service.dart';
import 'services/user_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Sans configuration Firebase, l'app tourne en mode local (pas de compte).
  final online = await ButeoFirebase.start();
  final repository = online ? await _liveTipsOrDemo() : DemoTipsRepository();

  // Paiement Google Play : seulement avec les vrais pronos (vérifié par le serveur).
  final billing = online && !repository.isDemo ? PlayBillingService(prefs) : null;
  final ads = AdMobService();

  final state = AppState(
    prefs,
    auth: online ? FirebaseAuthService() : const UnavailableAuthService(),
    store: online ? FirestoreUserStore() : const NoUserStore(),
    notifier: DeviceNotificationService(pushEnabled: online),
    demoMode: repository.isDemo,
    billing: billing ?? const UnavailableBillingService(),
    ads: ads,
    journalRemote: online ? FirestoreJournalRemote() : const NoJournalRemote(),
  );
  state.onAccessChanged = repository.refreshAccess;
  repository.addListener(state.tick);
  await state.start();

  runApp(
    ButeoApp(state: state, repository: repository, contest: repository.isDemo ? null : FirestoreContestRepository()),
  );

  // Après l'affichage : consentement publicitaire (Europe), puis bannières et prix Google Play.
  unawaited(ads.start().then((_) => state.tick()));
  if (billing != null) unawaited(billing.start().then((_) => state.refreshPrices()));
}

/// Vrais pronos dès que le moteur a publié au moins une fois, sinon démonstration.
Future<TipsRepository> _liveTipsOrDemo() async {
  try {
    final engine = await FirebaseFirestore.instance.doc('config/engine').get().timeout(const Duration(seconds: 6));
    if (engine.data()?['active'] == true) {
      final live = FirestoreTipsRepository();
      await live.start();
      return live;
    }
  } catch (e) {
    debugPrint('Moteur de pronostics injoignable, démonstration : $e');
  }
  return DemoTipsRepository();
}
