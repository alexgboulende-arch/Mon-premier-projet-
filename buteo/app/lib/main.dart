import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/tips_repository.dart';
import 'services/auth_service.dart';
import 'services/firebase_config.dart';
import 'services/notification_service.dart';
import 'services/user_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Sans configuration Firebase, l'app tourne en mode local (pas de compte).
  final online = await ButeoFirebase.start();
  final state = AppState(
    prefs,
    auth: online ? FirebaseAuthService() : const UnavailableAuthService(),
    store: online ? FirestoreUserStore() : const NoUserStore(),
    notifier: DeviceNotificationService(pushEnabled: online),
  );
  await state.start();

  runApp(ButeoApp(state: state, repository: DemoTipsRepository()));
}
