import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

/// Identifiants des produits à créer dans la Play Console (voir README).
abstract final class PlayProducts {
  static const pro = 'buteo_pro';
  static const elite = 'buteo_elite';
  static const coupon = 'coupon_vip';

  /// Forfaits de base de chaque abonnement, par durée en mois.
  static const basePlans = {1: 'mensuel', 3: 'trimestriel', 6: 'semestriel'};

  static String subscriptionFor(Tier tier) => tier == Tier.elite ? elite : pro;
}

/// Accès renvoyés par le serveur après vérification d'un achat.
class Entitlement {
  const Entitlement({required this.tier, this.tierUntil, this.coupons = const []});

  final Tier tier;
  final DateTime? tierUntil;
  final List<String> coupons;

  static Entitlement fromMap(Map<String, dynamic> m) => Entitlement(
    tier: Tier.values.firstWhere((t) => t.name == m['tier'], orElse: () => Tier.free),
    tierUntil: m['tierUntil'] is String ? DateTime.parse(m['tierUntil'] as String) : null,
    coupons: List<String>.from(m['coupons'] as List? ?? const []),
  );
}

/// Ce qui arrive après un achat (affiché à l'utilisateur).
sealed class BillingEvent {
  const BillingEvent();
}

class PurchaseGranted extends BillingEvent {
  const PurchaseGranted(this.entitlement, {required this.coupon});

  final Entitlement entitlement;
  final bool coupon;
}

class PurchasePending extends BillingEvent {
  const PurchasePending();
}

class PurchaseFailed extends BillingEvent {
  const PurchaseFailed(this.message);

  final String message;
}

abstract class BillingService {
  /// `false` hors Play Store ou sans Firebase (démonstration, tests).
  bool get available;

  Stream<BillingEvent> get events;

  /// Prix affichés par Google Play (« 2 900 FCFA »), par produit et forfait.
  Future<Map<String, String>> prices();

  Future<void> buySubscription(Tier tier, int months);

  Future<void> buyCoupon(Rubric rubric);

  /// Retrouve les abonnements achetés avec ce compte Google Play.
  Future<void> restore();
}

class UnavailableBillingService implements BillingService {
  const UnavailableBillingService();

  @override
  bool get available => false;

  @override
  Stream<BillingEvent> get events => const Stream.empty();

  @override
  Future<Map<String, String>> prices() async => const {};

  @override
  Future<void> buySubscription(Tier tier, int months) async {}

  @override
  Future<void> buyCoupon(Rubric rubric) async {}

  @override
  Future<void> restore() async {}
}

/// Paiement Google Play, vérifié par la fonction serveur `verifierAchatPlay`.
class PlayBillingService implements BillingService {
  PlayBillingService(this._prefs);

  final SharedPreferences _prefs;
  final _iap = InAppPurchase.instance;
  final _events = StreamController<BillingEvent>.broadcast();
  final _verify = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('verifierAchatPlay');
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<String, ProductDetails> _details = {};
  bool _available = false;

  /// Rubrique du coupon en cours d'achat, gardée si l'app est fermée avant la vérification.
  static const _kPendingRubric = 'pendingCouponRubric';

  @override
  bool get available => _available;

  @override
  Stream<BillingEvent> get events => _events.stream;

  Future<void> start() async {
    _available = await _iap.isAvailable();
    if (!_available) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('Achats : $e'));
    await _load();
  }

  Future<void> _load() async {
    final response = await _iap.queryProductDetails({PlayProducts.pro, PlayProducts.elite, PlayProducts.coupon});
    for (final d in response.productDetails) {
      _details[_key(d)] = d;
    }
    if (response.notFoundIDs.isNotEmpty) debugPrint('Produits absents de la Play Console : ${response.notFoundIDs}');
  }

  /// « buteo_pro/mensuel » pour un forfait d'abonnement, « coupon_vip » pour le coupon.
  static String _key(ProductDetails d) {
    if (d is GooglePlayProductDetails && d.subscriptionIndex != null) {
      return '${d.id}/${d.productDetails.subscriptionOfferDetails![d.subscriptionIndex!].basePlanId}';
    }
    return d.id;
  }

  @override
  Future<Map<String, String>> prices() async {
    if (_available && _details.isEmpty) await _load();
    return {for (final e in _details.entries) e.key: e.value.price};
  }

  @override
  Future<void> buySubscription(Tier tier, int months) async {
    final details = _details['${PlayProducts.subscriptionFor(tier)}/${PlayProducts.basePlans[months]}'];
    if (details == null) return _fail('Cette offre n’est pas encore disponible sur Google Play.');
    await _iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: details,
        offerToken: details is GooglePlayProductDetails ? details.offerToken : null,
      ),
    );
  }

  @override
  Future<void> buyCoupon(Rubric rubric) async {
    final details = _details[PlayProducts.coupon];
    if (details == null) return _fail('Le coupon n’est pas encore disponible sur Google Play.');
    await _prefs.setString(_kPendingRubric, rubric.id);
    await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: details));
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  void _fail(String message) => _events.add(PurchaseFailed(message));

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const PurchasePending());
        case PurchaseStatus.error:
          _fail('Le paiement n’a pas abouti. Aucun montant n’a été débité.');
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliver(p);
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> _deliver(PurchaseDetails p) async {
    final coupon = p.productID == PlayProducts.coupon;
    try {
      final result = await _verify.call<Map<String, dynamic>>({
        'kind': coupon ? 'coupon' : 'subscription',
        'productId': p.productID,
        'purchaseToken': p.verificationData.serverVerificationData,
        if (coupon) 'rubric': _prefs.getString(_kPendingRubric),
      });
      if (coupon) await _prefs.remove(_kPendingRubric);
      _events.add(PurchaseGranted(Entitlement.fromMap(Map<String, dynamic>.from(result.data)), coupon: coupon));
    } on FirebaseFunctionsException catch (e) {
      _fail(e.message ?? 'La vérification de l’achat a échoué. Réessaie dans un instant.');
    }
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
