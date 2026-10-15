import 'dart:async';

import 'package:buteo/data/models.dart';
import 'package:buteo/services/auth_service.dart';
import 'package:buteo/services/billing_service.dart';
import 'package:buteo/services/notification_service.dart';
import 'package:buteo/services/user_store.dart';

/// Compte simulé : la connexion réussit tout de suite.
class FakeAuthService implements AuthService {
  final _changes = StreamController<Account?>.broadcast();
  Account? _current;
  bool deleted = false;

  static const user = Account(uid: 'u1', name: 'Awa Koné', email: 'awa@example.com');

  @override
  bool get available => true;

  @override
  Account? get current => _current;

  @override
  Stream<Account?> get changes => _changes.stream;

  void _set(Account? a) {
    _current = a;
    _changes.add(a);
  }

  @override
  Future<void> signInWithGoogle() async => _set(user);

  @override
  Future<SmsStep> sendSmsCode(String phone, {int? resendToken}) async => const SmsCodeSent('verif-1', 7);

  @override
  Future<void> confirmSmsCode(String verificationId, String code) async {
    if (code != '123456') throw const AuthFailure('Code incorrect. Vérifie le SMS reçu.');
    _set(const Account(uid: 'u2', phone: '+2250700000000'));
  }

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<void> deleteAccount() async => deleted = true;
}

class FakeUserStore implements UserStore {
  final docs = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> load(String uid) async => docs[uid];

  @override
  Future<void> save(String uid, Map<String, dynamic> data) async => docs[uid] = {...?docs[uid], ...data};

  @override
  Future<void> delete(String uid) async => docs.remove(uid);

  final deletionRequests = <String>[];

  @override
  Future<void> requestDeletion(String uid) async => deletionRequests.add(uid);
}

class FakeNotificationService implements NotificationService {
  final applied = <Map<String, bool>>[];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> apply(Map<String, bool> settings) async => applied.add(Map.of(settings));

  @override
  Future<String?> pushToken() async => 'jeton-test';
}

/// Google Play simulé : chaque achat est accepté, comme si le serveur l'avait vérifié.
class FakeBillingService implements BillingService {
  FakeBillingService({this.available = true, String? today})
    : today = today ?? DateTime.now().toUtc().toIso8601String().substring(0, 10);

  @override
  final bool available;

  /// Jour du coupon, comme le fixe le serveur (« 2026-10-13 »).
  final String today;
  final _events = StreamController<BillingEvent>.broadcast();
  final bought = <String>[];

  @override
  Stream<BillingEvent> get events => _events.stream;

  @override
  Future<Map<String, String>> prices() async => {PlayProducts.coupon: '500 FCFA'};

  @override
  Future<void> buySubscription(Tier tier, int months) async {
    bought.add('${PlayProducts.subscriptionFor(tier)}/${PlayProducts.basePlans[months]}');
    _events.add(
      PurchaseGranted(
        Entitlement(
          tier: tier,
          tierUntil: DateTime.now().toUtc().add(Duration(days: 30 * months)),
        ),
        coupon: false,
      ),
    );
  }

  @override
  Future<void> buyCoupon(Rubric rubric) async {
    bought.add('${PlayProducts.coupon}:${rubric.id}');
    _events.add(PurchaseGranted(Entitlement(tier: Tier.free, coupons: ['$today|${rubric.id}']), coupon: true));
  }

  void pending() => _events.add(const PurchasePending());

  @override
  Future<void> restore() async {}
}
