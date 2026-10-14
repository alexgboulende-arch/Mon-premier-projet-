import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../services/firebase_config.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

/// Fenêtre de connexion : Google ou numéro de téléphone.
Future<void> showLoginSheet(BuildContext context) {
  final state = AppScope.read(context);
  return showButeoSheet<void>(context, (sheet) => [_LoginChoices(state: state, outer: context)]);
}

class _LoginChoices extends StatefulWidget {
  const _LoginChoices({required this.state, required this.outer});

  final AppState state;

  /// Contexte de l'écran sous la fenêtre, pour les messages et la suite.
  final BuildContext outer;

  @override
  State<_LoginChoices> createState() => _LoginChoicesState();
}

class _LoginChoicesState extends State<_LoginChoices> {
  bool _busy = false;

  Future<void> _google() async {
    // Le message s'affiche sur l'écran du dessous, une fois la fenêtre fermée.
    final messenger = ScaffoldMessenger.of(widget.outer);
    setState(() => _busy = true);
    try {
      await widget.state.signInWithGoogle();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Connecté avec Google')));
    } on AuthCancelled {
      // Fenêtre Google fermée : on reste ici.
    } on AuthFailure catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _phone() {
    Navigator.pop(context);
    Navigator.of(widget.outer).push(MaterialPageRoute<void>(builder: (_) => const PhoneLoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.state.auth.available;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Se connecter', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const MutedText(
          'Ton compte garde tes équipes favorites et tes alertes, même si tu changes de téléphone.',
          size: 13.5,
        ),
        const SizedBox(height: 14),
        WideButton(
          _busy ? 'Connexion…' : 'Continuer avec Google',
          icon: Icons.account_circle_outlined,
          onPressed: _busy ? () {} : (available ? _google : () => showToast(context, notConfiguredMessage)),
        ),
        if (ButeoFirebase.phoneSignIn) ...[
          const SizedBox(height: 10),
          WideButton(
            'Continuer avec mon numéro',
            icon: Icons.phone_iphone_rounded,
            tone: ButtonTone.ghost,
            onPressed: available ? _phone : () => showToast(context, notConfiguredMessage),
          ),
        ],
        if (!available) ...[const SizedBox(height: 12), const Note(notConfiguredMessage, icon: Icons.info_outline)],
      ],
    );
  }
}

/// Indicatifs des pays francophones les plus concernés, Côte d'Ivoire en premier.
const _countries = <(String, String)>[
  ('Côte d’Ivoire', '+225'),
  ('Sénégal', '+221'),
  ('Cameroun', '+237'),
  ('Bénin', '+229'),
  ('Burkina Faso', '+226'),
  ('Togo', '+228'),
  ('Mali', '+223'),
  ('Niger', '+227'),
  ('Guinée', '+224'),
  ('RD Congo', '+243'),
  ('Congo', '+242'),
  ('Gabon', '+241'),
  ('Madagascar', '+261'),
  ('Maroc', '+212'),
  ('Tunisie', '+216'),
  ('Algérie', '+213'),
  ('France', '+33'),
  ('Belgique', '+32'),
  ('Suisse', '+41'),
  ('Canada', '+1'),
];

/// Connexion par SMS : numéro, puis code à 6 chiffres.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _number = TextEditingController();
  final _code = TextEditingController();
  String _dial = _countries.first.$2;
  SmsCodeSent? _sent;
  bool _busy = false;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _phone {
    var digits = _number.text.replaceAll(RegExp(r'\D'), '');
    // En France, en Belgique et en Suisse, on retire le 0 du numéro national.
    if (const ['+33', '+32', '+41'].contains(_dial) && digits.startsWith('0')) digits = digits.substring(1);
    return '$_dial$digits';
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _send({bool again = false}) async {
    if (_number.text.replaceAll(RegExp(r'\D'), '').length < 6) {
      showToast(context, 'Entre ton numéro de téléphone.');
      return;
    }
    setState(() => _busy = true);
    try {
      final step = await AppScope.read(context).sendSmsCode(_phone, resendToken: again ? _sent?.resendToken : null);
      if (!mounted) return;
      switch (step) {
        case SmsAutoVerified():
          _done();
        case SmsCodeSent():
          setState(() => _sent = step);
          _startCountdown();
      }
    } on AuthFailure catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      showToast(context, 'Le code contient 6 chiffres.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.read(context).confirmSmsCode(_sent!.verificationId, code);
      if (mounted) _done();
    } on AuthFailure catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Connecté avec ton numéro')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = InputDecoration(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line),
      ),
    );
    final sent = _sent;
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion par SMS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          if (sent == null) ...[
            const Text('Ton numéro de téléphone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const MutedText('Tu vas recevoir un code par SMS pour confirmer que c’est bien toi.', size: 13.5),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _dial,
              isExpanded: true,
              decoration: field.copyWith(labelText: 'Pays'),
              items: [
                for (final (name, dial) in _countries) DropdownMenuItem(value: dial, child: Text('$name ($dial)')),
              ],
              onChanged: (v) => setState(() => _dial = v ?? _dial),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
              decoration: field.copyWith(labelText: 'Numéro', prefixText: '$_dial  '),
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 16),
            WideButton(_busy ? 'Envoi…' : 'Recevoir le code', onPressed: _busy ? () {} : _send),
          ] else ...[
            const Text('Code reçu par SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            MutedText('Envoyé au $_phone.', size: 13.5),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: numStyle(30).copyWith(letterSpacing: 10),
              decoration: field.copyWith(counterText: '', hintText: '••••••'),
              onChanged: (v) {
                if (v.length == 6) _confirm();
              },
            ),
            const SizedBox(height: 16),
            WideButton(_busy ? 'Vérification…' : 'Valider', onPressed: _busy ? () {} : _confirm),
            const SizedBox(height: 10),
            WideButton(
              _wait > 0 ? 'Renvoyer le code dans $_wait s' : 'Renvoyer le code',
              tone: ButtonTone.ghost,
              onPressed: _wait > 0 || _busy ? () {} : () => _send(again: true),
            ),
            TextButton(
              onPressed: () => setState(() {
                _sent = null;
                _code.clear();
              }),
              child: Text('Changer de numéro', style: TextStyle(color: c.muted)),
            ),
          ],
        ],
      ),
    );
  }
}
