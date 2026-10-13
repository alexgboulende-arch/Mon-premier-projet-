import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import 'splash_screen.dart';

const supportEmail = 'support@buteo.app';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final coupons = state.couponsOn(dayOf(AppScope.repo(context).now()));

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Eyebrow(title), const SizedBox(height: 10), child],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Panel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: c.surface2,
                child: Icon(Icons.person_outline_rounded, color: c.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Invité', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    MutedText('Formule ${state.tier.label} · $coupons coupon${coupons > 1 ? 's' : ''} aujourd\'hui'),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _showLogin(context),
                style: FilledButton.styleFrom(backgroundColor: c.win, foregroundColor: c.winInk),
                child: const Text('Se connecter'),
              ),
            ],
          ),
        ),
        section(
          'Mode démo',
          Column(
            children: [
              Segmented<Tier>(
                options: const [(Tier.free, 'Gratuit', null), (Tier.pro, 'Pro', null), (Tier.elite, 'Élite', null)],
                value: state.tier,
                onChanged: state.setTier,
              ),
              const SizedBox(height: 10),
              WideButton(
                'Remettre la démo à zéro',
                tone: ButtonTone.ghost,
                onPressed: () {
                  state.resetDemo();
                  showToast(context, 'Démo remise à zéro');
                },
              ),
            ],
          ),
        ),
        section(
          'Notifications',
          Panel(
            child: Column(
              children: [
                _SwitchRow('drop', 'Nouveaux pronos', 'Chaque nuit à 00:00'),
                _SwitchRow('results', 'Résultats', 'Quand un prono est gagné ou perdu'),
                _SwitchRow('live', 'Pronos live', 'Formule Élite'),
              ],
            ),
          ),
        ),
        section(
          'Apparence',
          Segmented<bool>(
            options: const [(false, 'Sombre', null), (true, 'Clair', null)],
            value: state.lightTheme,
            onChanged: state.setLightTheme,
          ),
        ),
        section(
          'Jeu responsable',
          Panel(
            child: Column(
              children: [
                _Row(
                  icon: Icons.pause_circle_outline_rounded,
                  title: 'Faire une pause',
                  subtitle: 'Masquer les pronos pendant 1, 7 ou 30 jours',
                  onTap: () => showToast(context, 'Disponible dans une prochaine version'),
                ),
                _Row(
                  icon: Icons.bedtime_outlined,
                  title: 'Limiter les rappels',
                  subtitle: 'Pas de notification après 23:00',
                  onTap: () => showToast(context, 'Disponible dans une prochaine version'),
                ),
                _Row(
                  icon: Icons.support_agent_outlined,
                  title: "Besoin d'aide ?",
                  subtitle: 'Joueurs Info Service (France) : joueurs-info-service.fr',
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'https://www.joueurs-info-service.fr'));
                    showToast(context, 'Adresse du site copiée');
                  },
                ),
              ],
            ),
          ),
        ),
        section(
          'Aide et informations',
          Panel(
            child: Column(
              children: [
                _Row(
                  icon: Icons.mail_outline_rounded,
                  title: 'Support',
                  subtitle: supportEmail,
                  trailing: Icons.copy_rounded,
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: supportEmail));
                    showToast(context, 'Adresse copiée');
                  },
                ),
                _Row(
                  icon: Icons.description_outlined,
                  title: 'Politique de confidentialité',
                  onTap: () => showToast(context, 'Page à rédiger avant la publication'),
                ),
                _Row(
                  icon: Icons.description_outlined,
                  title: "Conditions d'utilisation",
                  onTap: () => showToast(context, 'Page à rédiger avant la publication'),
                ),
                _Row(
                  icon: Icons.play_circle_outline_rounded,
                  title: "Revoir l'écran de démarrage",
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) => const SplashScreen(replay: true),
                      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(child: MutedText('Buteo 0.1 · version de démonstration', size: 11.5)),
      ],
    );
  }

  void _showLogin(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Se connecter', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const MutedText("Ton compte garde tes abonnements et tes coupons, même si tu changes de téléphone."),
              const SizedBox(height: 14),
              WideButton('Continuer avec Google', icon: Icons.account_circle_outlined, onPressed: () => _soon(sheet)),
              const SizedBox(height: 10),
              WideButton(
                'Continuer avec mon numéro',
                icon: Icons.phone_iphone_rounded,
                tone: ButtonTone.ghost,
                onPressed: () => _soon(sheet),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _soon(BuildContext sheet) {
    Navigator.pop(sheet);
    showToast(sheet, 'La connexion arrive avec la prochaine étape (Firebase)');
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.keyName, this.title, this.subtitle);

  final String keyName;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return _Divided(
      child: SwitchListTile(
        value: state.notifications[keyName]!,
        onChanged: (_) => state.toggleNotification(keyName),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
        subtitle: MutedText(subtitle, size: 12),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Divided(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: c.muted),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
        subtitle: subtitle == null ? null : MutedText(subtitle!, size: 12),
        trailing: Icon(trailing ?? Icons.chevron_right_rounded, size: 20, color: c.faint),
      ),
    );
  }
}

/// Trait de séparation entre les lignes d'un même bloc.
class _Divided extends StatelessWidget {
  const _Divided({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.line, width: .5)),
    ),
    // Material transparent : l'effet au toucher reste visible sur le fond du bloc.
    child: Material(type: MaterialType.transparency, child: child),
  );
}
