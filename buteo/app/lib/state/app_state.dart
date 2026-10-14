import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/tips_repository.dart';
import '../services/ads_service.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/notification_service.dart';
import '../services/user_store.dart';

/// Réglages, favoris et accès de l'utilisateur.
///
/// Tout est gardé sur le téléphone. Quand l'utilisateur est connecté, ses
/// favoris et ses alertes sont aussi enregistrés avec son compte, pour les
/// retrouver sur un autre téléphone. La formule et les coupons restent
/// simulés jusqu'à l'étape des paiements.
class AppState extends ChangeNotifier {
  AppState(
    this._prefs, {
    this.auth = const UnavailableAuthService(),
    this.store = const NoUserStore(),
    this.notifier = const SilentNotificationService(),
    this.demoMode = true,
    this.billing = const UnavailableBillingService(),
    this.ads = const NoAdsService(),
  }) {
    final saved = _prefs.getString(_kTier);
    _demoTier = Tier.values.firstWhere((t) => t.name == saved, orElse: () => Tier.free);
    _unlocked = {...?_prefs.getStringList(_kUnlocked)};
    _favorites = {...?_prefs.getStringList(_kFavorites)};
    lightTheme = _prefs.getBool(_kLight) ?? false;
    for (final k in notifications.keys.toList()) {
      notifications[k] = _prefs.getBool('notif_$k') ?? notifications[k]!;
    }
    account = auth.current;
  }

  static const _kTier = 'tier';
  static const _kUnlocked = 'unlocked';
  static const _kFavorites = 'favorites';
  static const _kLight = 'lightTheme';
  static const _kAskedNotif = 'askedNotificationPermission';

  final SharedPreferences _prefs;
  final AuthService auth;
  final UserStore store;
  final NotificationService notifier;
  final BillingService billing;
  final AdsService ads;
  StreamSubscription<Account?>? _accountSub;
  StreamSubscription<BillingEvent>? _billingSub;
  final _notices = StreamController<String>.broadcast();

  /// Messages à afficher (achat confirmé, paiement en attente…).
  Stream<String> get notices => _notices.stream;

  /// Prix affichés par Google Play, par produit et forfait (« buteo_pro/mensuel »).
  Map<String, String> playPrices = const {};

  /// Données de démonstration : la formule et les coupons sont simulés sur le
  /// téléphone. Avec les vraies données, ils viennent du serveur (profil Firestore).
  final bool demoMode;

  /// Appelé quand la formule ou les coupons changent (rechargement des rubriques VIP).
  VoidCallback? onAccessChanged;

  Tier _demoTier = Tier.free;
  Tier serverTier = Tier.free;
  DateTime? serverTierUntil;
  Set<String> _serverCoupons = {};

  /// Formule en cours : simulée en démonstration, sinon celle payée et pas encore échue.
  Tier get tier {
    if (demoMode) return _demoTier;
    final until = serverTierUntil;
    return until != null && until.isAfter(DateTime.now().toUtc()) ? serverTier : Tier.free;
  }

  Set<String> _unlocked = {};
  Set<String> _favorites = {};
  bool lightTheme = false;
  Account? account;
  final notifications = <String, bool>{Alerts.drop: true, Alerts.results: true, Alerts.live: false};

  /// Onglet affiché (0 Accueil, 1 Live, 2 Stats, 3 Offres, 4 Profil).
  int tab = 0;
  int statsDays = 30;
  int planMonths = 1;

  bool get showAds => tier == Tier.free;
  bool get signedIn => account != null;

  /// À appeler une fois au démarrage : programme les alertes et suit le compte.
  Future<void> start() async {
    _accountSub = auth.changes.listen(_onAccount);
    _billingSub = billing.events.listen(_onBilling);
    await notifier.apply(notifications);
    await refreshPrices();
  }

  /// Prix locaux affichés par Google Play.
  Future<void> refreshPrices() async {
    if (!billing.available) return;
    playPrices = await billing.prices();
    notifyListeners();
  }

  @override
  void dispose() {
    _accountSub?.cancel();
    _billingSub?.cancel();
    _notices.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Achats Google Play (vraies données)

  Future<void> buySubscription(Tier t, int months) => billing.buySubscription(t, months);

  Future<void> buyCoupon(Rubric r) => billing.buyCoupon(r);

  Future<void> restorePurchases() => billing.restore();

  void _onBilling(BillingEvent e) {
    switch (e) {
      case PurchaseGranted(:final entitlement, :final coupon):
        serverTier = entitlement.tier;
        serverTierUntil = entitlement.tierUntil;
        _serverCoupons = {...entitlement.coupons};
        onAccessChanged?.call();
        notifyListeners();
        _notices.add(coupon ? 'Coupon débloqué pour aujourd’hui' : 'Bienvenue dans la formule ${tier.label}');
      case PurchasePending():
        _notices.add('Paiement en attente : l’accès s’ouvrira dès sa confirmation par Google Play.');
      case PurchaseFailed(:final message):
        _notices.add(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Formule et coupons (simulés)

  /// Coupons débloqués : « 2026-10-13|score ».
  static String _couponKey(String rubricId, DateTime day) => '${dateKey(day)}|$rubricId';

  Set<String> get _coupons => demoMode ? _unlocked : _serverCoupons;

  bool canSee(Rubric r, DateTime day) => tier.includes(r.tier) || _coupons.contains(_couponKey(r.id, day));

  int couponsOn(DateTime day) => _coupons.where((k) => k.startsWith('${dateKey(day)}|')).length;

  void unlock(Rubric r, DateTime day) {
    _unlocked.add(_couponKey(r.id, day));
    _prefs.setStringList(_kUnlocked, _unlocked.toList());
    notifyListeners();
  }

  void setTier(Tier t) {
    _demoTier = t;
    _prefs.setString(_kTier, t.name);
    notifyListeners();
  }

  void resetDemo() {
    _unlocked.clear();
    _prefs.remove(_kUnlocked);
    setTier(Tier.free);
  }

  // ---------------------------------------------------------------------------
  // Équipes favorites

  static String favoriteKey(Sport sport, String team) => '${sport.name}:$team';

  bool isFavorite(Sport sport, String team) => _favorites.contains(favoriteKey(sport, team));

  int get favoriteCount => _favorites.length;

  /// Le match concerne-t-il une équipe suivie ?
  bool followsFixture(Fixture f) => isFavorite(f.sport, f.home) || isFavorite(f.sport, f.away);

  void toggleFavorite(Sport sport, String team) {
    final key = favoriteKey(sport, team);
    if (!_favorites.remove(key)) _favorites.add(key);
    _prefs.setStringList(_kFavorites, _favorites.toList());
    notifyListeners();
    _pushToAccount();
  }

  // ---------------------------------------------------------------------------
  // Alertes

  void toggleNotification(String key) {
    notifications[key] = !notifications[key]!;
    _prefs.setBool('notif_$key', notifications[key]!);
    notifyListeners();
    notifier.apply(notifications);
    _pushToAccount();
  }

  /// Demande l'autorisation des notifications une seule fois, au premier lancement.
  Future<void> askNotificationPermissionOnce() async {
    if (_prefs.getBool(_kAskedNotif) ?? false) return;
    await _prefs.setBool(_kAskedNotif, true);
    await notifier.requestPermission();
    await notifier.apply(notifications);
  }

  // ---------------------------------------------------------------------------
  // Compte

  Future<void> signInWithGoogle() => auth.signInWithGoogle();

  Future<SmsStep> sendSmsCode(String phone, {int? resendToken}) => auth.sendSmsCode(phone, resendToken: resendToken);

  Future<void> confirmSmsCode(String verificationId, String code) => auth.confirmSmsCode(verificationId, code);

  Future<void> signOut() => auth.signOut();

  /// Efface les données en ligne puis le compte. Les réglages restent sur le téléphone.
  Future<void> deleteAccount() async {
    final uid = account?.uid;
    if (uid == null) return;
    await store.delete(uid);
    await auth.deleteAccount();
    await auth.signOut();
  }

  Future<void> _onAccount(Account? a) async {
    final previous = account?.uid;
    account = a;
    if (a == null) {
      serverTier = Tier.free;
      serverTierUntil = null;
      _serverCoupons = {};
      if (previous != null) onAccessChanged?.call();
    }
    notifyListeners();
    if (a == null || a.uid == previous) return;
    // Nouvelle connexion : on fusionne ce qui est sur le téléphone et ce qui est en ligne.
    try {
      final remote = await store.load(a.uid);
      _readAccess(remote);
      if (remote != null) {
        _favorites.addAll(List<String>.from(remote['favorites'] as List? ?? const []));
        final alerts = remote['notifications'];
        if (alerts is Map) {
          for (final k in notifications.keys.toList()) {
            if (alerts[k] is bool) notifications[k] = alerts[k] as bool;
          }
        }
        await _prefs.setStringList(_kFavorites, _favorites.toList());
        for (final e in notifications.entries) {
          await _prefs.setBool('notif_${e.key}', e.value);
        }
        notifyListeners();
        await notifier.apply(notifications);
      }
      await _pushToAccount(withToken: true);
    } catch (e) {
      debugPrint('Synchronisation du compte : $e');
    }
  }

  /// Formule et coupons écrits par le serveur dans le profil.
  void _readAccess(Map<String, dynamic>? remote) {
    final saved = remote?['tier'];
    serverTier = Tier.values.firstWhere((t) => t.name == saved, orElse: () => Tier.free);
    final until = remote?['tierUntil'];
    serverTierUntil = until is DateTime ? until : null;
    _serverCoupons = {...List<String>.from(remote?['coupons'] as List? ?? const [])};
    onAccessChanged?.call();
    notifyListeners();
  }

  Future<void> _pushToAccount({bool withToken = false}) async {
    final uid = account?.uid;
    if (uid == null) return;
    try {
      final token = withToken ? await notifier.pushToken() : null;
      await store.save(uid, {
        'favorites': _favorites.toList()..sort(),
        'notifications': notifications,
        'pushToken': ?token,
      });
    } catch (e) {
      debugPrint('Enregistrement du compte : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation et affichage

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
