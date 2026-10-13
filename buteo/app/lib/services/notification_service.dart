import 'dart:ui' show Color;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Les alertes que l'utilisateur peut activer dans son profil.
abstract final class Alerts {
  /// Rappel local chaque nuit à 00:00 GMT, quand les pronos sont publiés.
  static const drop = 'drop';

  /// Résultats des pronos (envoyés par le serveur à partir de l'étape 3).
  static const results = 'results';

  /// Pronos live, formule Élite (envoyés par le serveur à partir de l'étape 3).
  static const live = 'live';
}

abstract class NotificationService {
  /// Demande l'autorisation d'afficher des notifications (Android 13 et plus).
  Future<bool> requestPermission();

  /// Programme ou annule les alertes selon les réglages.
  Future<void> apply(Map<String, bool> settings);

  /// Jeton d'envoi du téléphone, à enregistrer avec le compte.
  Future<String?> pushToken();
}

class SilentNotificationService implements NotificationService {
  const SilentNotificationService();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> apply(Map<String, bool> settings) async {}

  @override
  Future<String?> pushToken() async => null;
}

class DeviceNotificationService implements NotificationService {
  DeviceNotificationService({required this.pushEnabled});

  /// Firebase est configuré : les alertes serveur passent par Firebase Cloud Messaging.
  final bool pushEnabled;

  static const _dropId = 1;
  final _local = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
    );
    // Canal des alertes envoyées par le serveur (résultats, live), déclaré dans le manifeste.
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'alertes',
            'Résultats et live',
            description: 'Résultats des pronos et pronos en direct',
            importance: Importance.high,
          ),
        );
  }();

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      if (pushEnabled) await FirebaseMessaging.instance.requestPermission();
      return granted;
    } catch (e) {
      debugPrint('Autorisation des notifications : $e');
      return false;
    }
  }

  @override
  Future<void> apply(Map<String, bool> settings) async {
    try {
      await _init();
      await _local.cancel(id: _dropId);
      if (settings[Alerts.drop] ?? false) await _scheduleDrop();
      if (pushEnabled) {
        final fcm = FirebaseMessaging.instance;
        for (final topic in [Alerts.results, Alerts.live]) {
          if (settings[topic] ?? false) {
            await fcm.subscribeToTopic(topic);
          } else {
            await fcm.unsubscribeFromTopic(topic);
          }
        }
      }
    } catch (e) {
      debugPrint('Notifications : $e');
    }
  }

  Future<void> _scheduleDrop() {
    final now = tz.TZDateTime.now(tz.UTC);
    final midnight = tz.TZDateTime(tz.UTC, now.year, now.month, now.day).add(const Duration(days: 1));
    return _local.zonedSchedule(
      id: _dropId,
      scheduledDate: midnight,
      title: 'Les pronos du jour sont en ligne',
      body: 'Toutes les rubriques sont à jour. Joue avec modération.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'pronos',
          'Nouveaux pronos',
          channelDescription: 'Publication des pronos chaque nuit à 00:00 GMT',
          color: Color(0xFF2BF59A),
        ),
      ),
      // Heure approximative (quelques minutes) : pas besoin de l'autorisation « alarmes exactes ».
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<String?> pushToken() async {
    if (!pushEnabled) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Jeton push : $e');
      return null;
    }
  }
}
