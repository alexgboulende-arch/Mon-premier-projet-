import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuration du projet Firebase de Buteo.
///
/// Tant que ces valeurs sont vides, l'app fonctionne sans compte : favoris et
/// réglages restent sur le téléphone. Elles se trouvent dans le fichier
/// `google-services.json` téléchargé depuis la console Firebase (voir README).
abstract final class ButeoFirebase {
  /// `client[0].api_key[0].current_key`
  static const apiKey = '';

  /// `client[0].client_info.mobilesdk_app_id`
  static const appId = '';

  /// `project_info.project_number`
  static const messagingSenderId = '';

  /// `project_info.project_id`
  static const projectId = '';

  /// `project_info.storage_bucket`
  static const storageBucket = '';

  /// ID client OAuth de type « Web » (`client[0].oauth_client` avec `client_type` 3),
  /// créé par Firebase quand la connexion Google est activée.
  static const googleWebClientId = '';

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
