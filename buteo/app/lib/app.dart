import 'package:flutter/material.dart';

import 'data/tips_repository.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/shell.dart';

class ButeoApp extends StatelessWidget {
  const ButeoApp({
    super.key,
    required this.state,
    required this.repository,
    this.splashDuration = const Duration(milliseconds: 1400),
  });

  final AppState state;
  final TipsRepository repository;
  final Duration splashDuration;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      repository: repository,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Buteo',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(ButeoColors.light, Brightness.light),
          darkTheme: buildTheme(ButeoColors.dark, Brightness.dark),
          themeMode: state.lightTheme ? ThemeMode.light : ThemeMode.dark,
          home: SplashGate(duration: splashDuration, child: const Shell()),
        ),
      ),
    );
  }
}
