import 'package:cloud_firestore/cloud_firestore.dart';

/// Données du compte gardées en ligne, pour les retrouver sur un autre téléphone.
///
/// Document `users/{uid}` : `favorites` (liste), `notifications` (carte),
/// `pushToken`. La formule et les achats seront écrits par le serveur
/// (étape 4) et ne sont pas modifiables depuis l'app (voir firestore.rules).
abstract class UserStore {
  Future<Map<String, dynamic>?> load(String uid);

  Future<void> save(String uid, Map<String, dynamic> data);

  Future<void> delete(String uid);
}

class NoUserStore implements UserStore {
  const NoUserStore();

  @override
  Future<Map<String, dynamic>?> load(String uid) async => null;

  @override
  Future<void> save(String uid, Map<String, dynamic> data) async {}

  @override
  Future<void> delete(String uid) async {}
}

class FirestoreUserStore implements UserStore {
  FirestoreUserStore();

  final _users = FirebaseFirestore.instance.collection('users');

  @override
  Future<Map<String, dynamic>?> load(String uid) async => (await _users.doc(uid).get()).data();

  @override
  Future<void> save(String uid, Map<String, dynamic> data) =>
      _users.doc(uid).set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  @override
  Future<void> delete(String uid) => _users.doc(uid).delete();
}
