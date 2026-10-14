import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import 'screens/home_screen.dart';
import 'screens/live_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/stats_screen.dart';
import 'widgets/common.dart';
import 'widgets/sheets.dart';

/// Écran principal : en-tête, onglet affiché et barre d'onglets.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  Timer? _tick;
  StreamSubscription<String>? _notices;

  static const _titles = [null, 'En direct', 'Statistiques', 'Offres', 'Profil'];
  static const _pages = [HomeScreen(), LiveScreen(), StatsScreen(), OffersScreen(), ProfileScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Met à jour les scores et les états chaque minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => AppScope.read(context).tick());
    // Premier lancement : demande l'autorisation d'envoyer les alertes de 00:00.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      state.askNotificationPermissionOnce();
      // Résultat des achats (confirmé, en attente, refusé), quel que soit l'écran affiché.
      _notices = state.notices.listen((message) {
        if (mounted) showToast(context, message);
      });
    });
  }

  /// Retour dans l'app (après un paiement sur le site, par exemple) : on relit l'accès du compte.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) AppScope.read(context).refreshAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _notices?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final title = _titles[state.tab];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: title != null
            ? Text(title)
            : const Row(
                children: [
                  ButeoLogo(width: 40),
                  SizedBox(width: 8),
                  Text('BUTEO', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: .8)),
                ],
              ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => showNotificationsSheet(context),
            icon: Badge(smallSize: 8, backgroundColor: c.loss, child: const Icon(Icons.notifications_none_rounded)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: KeyedSubtree(key: ValueKey(state.tab), child: _pages[state.tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.tab,
        onDestinationSelected: state.setTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors_rounded),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium_rounded),
            label: 'Offres',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
