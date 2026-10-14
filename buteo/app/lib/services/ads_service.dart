import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Publicités AdMob de la version gratuite.
///
/// Identifiants de TEST de Google pour l'instant : à remplacer par ceux du
/// compte AdMob de Buteo (ici et dans AndroidManifest.xml) avant la publication.
abstract final class AdIds {
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
}

abstract class AdsService {
  /// `true` quand une bannière peut être chargée (consentement obtenu si nécessaire).
  bool get ready;
}

class NoAdsService implements AdsService {
  const NoAdsService();

  @override
  bool get ready => false;
}

class AdMobService implements AdsService {
  bool _ready = false;

  @override
  bool get ready => _ready;

  /// Demande le consentement là où la loi l'exige (Europe), puis démarre AdMob.
  Future<void> start() async {
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('Consentement : ${error.message}');
          if (!done.isCompleted) done.complete();
        }),
        (error) {
          debugPrint('Consentement : ${error.message}');
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _ready = true;
    } catch (e) {
      debugPrint('Publicités indisponibles : $e');
    }
  }
}
