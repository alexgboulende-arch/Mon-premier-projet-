import 'dart:async';

import 'package:buteo/services/auth_service.dart';
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
