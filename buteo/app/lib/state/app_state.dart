import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/tips_repository.dart';

/// Réglages et accès de l'utilisateur, gardés sur le téléphone.
///
/// Dans cette version, la formule et les coupons sont simulés : il n'y a
/// pas encore de compte ni de paiement réel.
class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    final saved = _prefs.getString(_kTier);
    tier = Tier.values.firstWhere((t) => t.name == saved, orElse: () => Tier.free);
    _unlocked = {...?_prefs.getStringList(_kUnlocked)};
    lightTheme = _prefs.getBool(_kLight) ?? false;
    for (final k in notifications.keys.toList()) {
      notifications[k] = _prefs.getBool('notif_$k') ?? notifications[k]!;
    }
  }

  static const _kTier = 'tier';
  static const _kUnlocked = 'unlocked';
  static const _kLight = 'lightTheme';

  final SharedPreferences _prefs;

  Tier tier = Tier.free;
  Set<String> _unlocked = {};
  bool lightTheme = false;
  final notifications = <String, bool>{'drop': true, 'results': true, 'live': false};

  /// Onglet affiché (0 Accueil, 1 Live, 2 Stats, 3 Offres, 4 Profil).
  int tab = 0;
  int statsDays = 30;
  int planMonths = 1;

  bool get showAds => tier == Tier.free;

  /// Coupons débloqués : « 2026-10-13|score ».
  static String _couponKey(String rubricId, DateTime day) => '${dateKey(day)}|$rubricId';

  bool canSee(Rubric r, DateTime day) => tier.includes(r.tier) || _unlocked.contains(_couponKey(r.id, day));

  int couponsOn(DateTime day) => _unlocked.where((k) => k.startsWith('${dateKey(day)}|')).length;

  void unlock(Rubric r, DateTime day) {
    _unlocked.add(_couponKey(r.id, day));
    _prefs.setStringList(_kUnlocked, _unlocked.toList());
    notifyListeners();
  }

  void setTier(Tier t) {
    tier = t;
    _prefs.setString(_kTier, t.name);
    notifyListeners();
  }

  void resetDemo() {
    _unlocked.clear();
    _prefs.remove(_kUnlocked);
    setTier(Tier.free);
  }

  /// Rafraîchit les écrans (scores en direct, compte à rebours).
  void tick() => notifyListeners();

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void setStatsDays(int d) {
    statsDays = d;
    notifyListeners();
  }

  void setPlanMonths(int m) {
    planMonths = m;
    notifyListeners();
  }

  void toggleNotification(String key) {
    notifications[key] = !notifications[key]!;
    _prefs.setBool('notif_$key', notifications[key]!);
    notifyListeners();
  }

  void setLightTheme(bool v) {
    lightTheme = v;
    _prefs.setBool(_kLight, v);
    notifyListeners();
  }
}

/// Donne accès à l'état et aux pronos dans tout l'arbre de widgets.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required this.repository, required super.child})
    : super(notifier: state);

  final TipsRepository repository;

  /// À utiliser dans `build` : le widget se reconstruit quand l'état change.
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// À utiliser dans les actions (boutons…), sans abonnement.
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static TipsRepository repo(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.repository;
}
