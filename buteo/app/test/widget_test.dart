import 'package:buteo/app.dart';
import 'package:buteo/data/tips_repository.dart';
import 'package:buteo/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Démarre l'app sur un écran de téléphone courant (360 × 780) à 20:10 GMT.
Future<AppState> startApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final state = AppState(await SharedPreferences.getInstance());
  await tester.pumpWidget(
    ButeoApp(
      state: state,
      repository: DemoTipsRepository(clock: () => DateTime.utc(2026, 10, 13, 20, 10)),
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
}
