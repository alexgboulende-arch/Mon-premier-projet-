import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuration du projet Firebase de Buteo.
///
/// Projet `buteo-bbec5`. Valeurs tirées du fichier `google-services.json`
/// téléchargé depuis la console Firebase (voir README) : ce sont des
/// identifiants publics, la sécurité repose sur les règles Firestore.
/// Si elles sont vides, l'app fonctionne sans compte : favoris et réglages
/// restent sur le téléphone.
abstract final class ButeoFirebase {
  /// `client[0].api_key[0].current_key`
  static const apiKey = 'AIzaSyAiho6O_-xrO2rVs_D_b-8pOmViRTajyjU';

  /// `client[0].client_info.mobilesdk_app_id`
  static const appId = '1:823242305441:android:4d02be9ff6a45fcad3e5e0';

  /// `project_info.project_number`
  static const messagingSenderId = '823242305441';

  /// `project_info.project_id`
  static const projectId = 'buteo-bbec5';

  /// `project_info.storage_bucket`
  static const storageBucket = 'buteo-bbec5.firebasestorage.app';

  /// ID client OAuth de type « Web » (`client[0].oauth_client` avec `client_type` 3),
  /// créé par Firebase quand la connexion Google est activée.
  static const googleWebClientId = '823242305441-4aca7ugvmdgscffeodh51dgek9tp54gj.apps.googleusercontent.com';

  /// Connexion par SMS : désactivée tant que le forfait Blaze n'est pas pris
  /// (Firebase facture les SMS). Passer à `true` pour afficher le bouton.
  static const phoneSignIn = false;

  static bool get isConfigured => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  /// Démarre Firebase. Renvoie `false` si la configuration manque ou échoue :
  /// l'app continue alors en mode local.
  static Future<bool> start() async {
    if (!isConfigured) return false;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Firebase indisponible : $e');
      return false;
    }
  }
}
