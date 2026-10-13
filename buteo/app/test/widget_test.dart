import 'package:buteo/app.dart';
import 'package:buteo/data/catalog.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

final _now = DateTime.utc(2026, 10, 13, 20, 10);

/// Démarre l'app sur un écran de téléphone courant (360 × 780) à 20:10 GMT.
Future<AppState> startApp(WidgetTester tester, {AppState? state}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (state == null) {
    SharedPreferences.setMockInitialValues({});
    state = AppState(await SharedPreferences.getInstance());
  }
  await tester.pumpWidget(
    ButeoApp(
      state: state,
      repository: DemoTipsRepository(clock: () => _now),
      splashDuration: const Duration(milliseconds: 10),
    ),
  );
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(seconds: 1));
  return state;
}

/// L'animation du point « en direct » tourne en boucle : on avance le temps
/// au lieu d'attendre que tout s'arrête.
/// Fait défiler jusqu'à l'élément, l'amène à l'écran, puis le touche.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200);
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets("l'accueil affiche les rubriques gratuites et VIP", (tester) async {
    await startApp(tester);
    expect(find.text('Pronos du jour'.toUpperCase()), findsOneWidget);
    expect(find.text('Mardi 13 octobre'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gratuit'), 300);
    expect(find.text('Gratuit'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Combiné cote 5+'), 300);
    expect(find.text('Combiné cote 5+'), findsOneWidget);
    expect(find.text('Combiné cote 50+'), findsNothing);
  });

  testWidgets('un coupon débloque une rubrique VIP pour la journée', (tester) async {
    await startApp(tester);
    await scrollAndTap(tester, find.text('Score exact'));
    expect(find.text('Rubrique Élite'), findsOneWidget);

    await tester.tap(find.textContaining('Débloquer ce coupon'));
    await settle(tester);
    await tester.tap(find.textContaining('Payer'));
    await settle(tester);
    expect(find.text('Rubrique Élite'), findsNothing);
    expect(find.textContaining("Pronos générés par l'IA"), findsOneWidget);
  });

  testWidgets('tous les onglets s’ouvrent sans erreur de mise en page', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    final state = await startApp(tester);
    for (final label in ['Live', 'Stats', 'Offres', 'Profil', 'Accueil']) {
      await tester.tap(find.text(label).last);
      await settle(tester);
    }
    expect(state.tab, 0);

    await tester.tap(find.text('Offres').last);
    await settle(tester);
    await scrollAndTap(tester, find.text('Choisir Pro'));
    await tester.tap(find.text("S'abonner"));
    await settle(tester);
    expect(state.tier.name, 'pro');
    expect(find.text('Ta formule actuelle'), findsOneWidget);

    await tester.tap(find.text('Profil').last);
    await settle(tester);
    await scrollAndTap(tester, find.text('Clair'));
    expect(state.lightTheme, isTrue);
  });

  testWidgets('suivre une équipe affiche ses matchs du jour sur l’accueil', (tester) async {
    final state = await startApp(tester);
    final team = DemoTipsRepository(clock: () => _now)
        .day(rubricsById['selection']!, dayOf(_now))
        .tips
        .first
        .fixture
        .home;

    await scrollAndTap(tester, find.text('Choisir'));
    expect(find.text('Mes équipes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), team);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, team).first);
    await settle(tester);
    expect(state.favoriteCount, 1);

    await tester.pageBack();
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Modifier'), 200);
    expect(find.text('Mes équipes'), findsOneWidget);
    expect(find.text('Suis tes équipes'), findsNothing);
  });

  testWidgets('connecté, le profil montre le compte et permet de le supprimer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = FakeAuthService();
    final store = FakeUserStore();
    final state = AppState(await SharedPreferences.getInstance(), auth: auth, store: store);
    await state.start();
    await startApp(tester, state: state);
    await state.signInWithGoogle();
    await settle(tester);

    await tester.tap(find.text('Profil').last);
    await settle(tester);
    expect(find.text('Awa Koné'), findsOneWidget);
    expect(find.text('Se connecter'), findsNothing);

    await scrollAndTap(tester, find.text('Supprimer mon compte'));
    await tester.tap(find.text('Supprimer définitivement'));
    await settle(tester);
    expect(auth.deleted, isTrue);
    expect(state.signedIn, isFalse);
    expect(find.text('Supprimer mon compte'), findsNothing);
    await tester.scrollUntilVisible(find.text('Invité'), -300);
    expect(find.text('Invité'), findsOneWidget);
  });

  testWidgets('sans Firebase, la fenêtre de connexion explique pourquoi', (tester) async {
    await startApp(tester);
    await tester.tap(find.text('Profil').last);
    await settle(tester);
    await tester.tap(find.text('Se connecter'));
    await settle(tester);
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.textContaining('projet Firebase'), findsOneWidget);
  });
}
