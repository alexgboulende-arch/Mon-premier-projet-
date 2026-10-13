import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_config.dart';

/// Compte Buteo de l'utilisateur connecté.
class Account {
  const Account({required this.uid, this.name, this.email, this.phone});

  final String uid;
  final String? name;
  final String? email;
  final String? phone;

  String get label => name ?? phone ?? email ?? 'Compte Buteo';

  /// Ce qui s'affiche sous le nom : l'adresse ou le numéro.
  String? get contact => name == null ? null : (email ?? phone);
}

/// Erreur à montrer telle quelle à l'utilisateur.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// L'utilisateur a fermé la fenêtre de connexion : rien à afficher.
class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// Résultat de l'envoi d'un SMS de vérification.
sealed class SmsStep {
  const SmsStep();
}

/// Le code est parti : il faut le saisir.
class SmsCodeSent extends SmsStep {
  const SmsCodeSent(this.verificationId, this.resendToken);

  final String verificationId;
  final int? resendToken;
}

/// Android a lu le SMS tout seul : l'utilisateur est déjà connecté.
class SmsAutoVerified extends SmsStep {
  const SmsAutoVerified();
}

abstract class AuthService {
  /// `false` tant que Firebase n'est pas configuré.
  bool get available;

  Account? get current;

  Stream<Account?> get changes;

  Future<void> signInWithGoogle();

  /// [phone] au format international, par exemple « +2250701020304 ».
  Future<SmsStep> sendSmsCode(String phone, {int? resendToken});

  Future<void> confirmSmsCode(String verificationId, String code);

  Future<void> signOut();

  /// Supprime le compte de connexion (les données sont effacées avant, par l'appelant).
  Future<void> deleteAccount();
}

const notConfiguredMessage = 'La connexion sera disponible dès que le projet Firebase de Buteo sera configuré.';

/// Utilisé tant que Firebase n'est pas configuré.
class UnavailableAuthService implements AuthService {
  const UnavailableAuthService();

  @override
  bool get available => false;

  @override
  Account? get current => null;

  @override
  Stream<Account?> get changes => const Stream.empty();

  Never _fail() => throw const AuthFailure(notConfiguredMessage);

  @override
  Future<void> signInWithGoogle() async => _fail();

  @override
  Future<SmsStep> sendSmsCode(String phone, {int? resendToken}) async => _fail();

  @override
  Future<void> confirmSmsCode(String verificationId, String code) async => _fail();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService();

  final _auth = FirebaseAuth.instance;
  Future<void>? _googleReady;

  @override
  bool get available => true;

  @override
  Account? get current => _toAccount(_auth.currentUser);

  @override
  Stream<Account?> get changes => _auth.userChanges().map(_toAccount);

  static Account? _toAccount(User? u) => u == null
      ? null
      : Account(
          uid: u.uid,
          name: (u.displayName?.isEmpty ?? true) ? null : u.displayName,
          email: u.email,
          phone: u.phoneNumber,
        );

  @override
  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    _googleReady ??= google.initialize(
      serverClientId: ButeoFirebase.googleWebClientId.isEmpty ? null : ButeoFirebase.googleWebClientId,
    );
    try {
      await _googleReady;
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthFailure('Google n’a pas renvoyé d’identifiant. Réessaie.');
      await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const AuthCancelled();
      throw AuthFailure('La connexion Google a échoué (${e.code.name}).');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  @override
  Future<SmsStep> sendSmsCode(String phone, {int? resendToken}) {
    final done = Completer<SmsStep>();
    _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        // Android a reconnu le SMS automatiquement.
        try {
          await _auth.signInWithCredential(credential);
          if (!done.isCompleted) done.complete(const SmsAutoVerified());
        } on FirebaseAuthException catch (e) {
          if (!done.isCompleted) done.completeError(AuthFailure(_message(e)));
        }
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(AuthFailure(_message(e)));
      },
      codeSent: (id, token) {
        if (!done.isCompleted) done.complete(SmsCodeSent(id, token));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return done.future;
  }

  @override
  Future<void> confirmSmsCode(String verificationId, String code) async {
    try {
      await _auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code));
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Pas connecté avec Google : rien à faire.
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
    'invalid-phone-number' => 'Ce numéro n’est pas valide. Vérifie l’indicatif du pays.',
    'too-many-requests' => 'Trop de tentatives. Réessaie dans quelques minutes.',
    'quota-exceeded' => 'Trop de SMS envoyés aujourd’hui. Réessaie plus tard.',
    'invalid-verification-code' => 'Code incorrect. Vérifie le SMS reçu.',
    'session-expired' || 'code-expired' => 'Le code a expiré. Demande un nouveau code.',
    'network-request-failed' => 'Pas de connexion internet. Vérifie ton réseau.',
    'operation-not-allowed' || 'billing-not-enabled' => 'Ce mode de connexion n’est pas encore activé.',
    'user-disabled' => 'Ce compte a été désactivé.',
    'requires-recent-login' => 'Par sécurité, reconnecte-toi puis recommence.',
    'account-exists-with-different-credential' =>
      'Un compte existe déjà avec cette adresse. Connecte-toi avec le moyen utilisé la première fois.',
    _ => 'La connexion a échoué (${e.code}).',
  };
}
