import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'favorites_screen.dart';
import 'journal_screen.dart';
import 'login.dart';
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
                    Text(
                      state.account?.label ?? 'Invité',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    if (state.account?.contact != null) MutedText(state.account!.contact!),
                    MutedText('Formule ${state.tier.label} · $coupons coupon${coupons > 1 ? 's' : ''} aujourd\'hui'),
                  ],
                ),
              ),
              if (!state.signedIn)
                FilledButton(
                  onPressed: () => showLoginSheet(context),
                  style: FilledButton.styleFrom(backgroundColor: c.win, foregroundColor: c.winInk),
                  child: const Text('Se connecter'),
                ),
            ],
          ),
        ),
        if (state.demoMode)
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
          'Mes paris',
          Panel(
            child: ListenableBuilder(
              listenable: state.journal,
              builder: (context, _) {
                final stats = state.journal.stats;
                return _Row(
                  icon: Icons.menu_book_outlined,
                  title: 'Journal de paris',
                  subtitle: stats.count == 0
                      ? 'Suis tes gains et tes pertes'
                      : '${stats.count} pari${stats.count > 1 ? 's' : ''} · ${signedFcfa(stats.profit)}',
                  onTap: () => openJournal(context),
                );
              },
            ),
          ),
        ),
        section(
          'Mes équipes',
          Panel(
            child: _Row(
              icon: Icons.star_outline_rounded,
              title: 'Équipes suivies',
              subtitle: state.favoriteCount == 0
                  ? 'Aucune pour l’instant'
                  : '${state.favoriteCount} équipe${state.favoriteCount > 1 ? 's' : ''}',
              onTap: () => openFavorites(context),
            ),
          ),
        ),
        section(
          'Notifications',
          Panel(
            child: Column(
              children: [
                _SwitchRow(Alerts.drop, 'Nouveaux pronos', 'Chaque nuit à 00:00'),
                _SwitchRow(Alerts.results, 'Résultats', 'Quand un prono est gagné ou perdu'),
                _SwitchRow(Alerts.live, 'Pronos live', 'Formule Élite'),
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
        if (state.signedIn)
          section(
            'Compte',
            Panel(
              child: Column(
                children: [
                  _Row(
                    icon: Icons.logout_rounded,
                    title: 'Se déconnecter',
                    onTap: () async {
                      await state.signOut();
                      if (context.mounted) showToast(context, 'Tu es déconnecté');
                    },
                  ),
                  _Row(
                    icon: Icons.delete_outline_rounded,
                    title: 'Supprimer mon compte',
                    subtitle: 'Efface ton compte et les données enregistrées en ligne',
                    danger: true,
                    onTap: () => _confirmDelete(context),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        Center(child: MutedText('Buteo 0.5', size: 11.5)),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final c = context.colors;
    final state = AppScope.read(context);
    final ok = await showButeoSheet<bool>(
      context,
      (sheet) => [
        const Text('Supprimer ton compte ?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const MutedText(
          'Ton compte et tes données en ligne (équipes suivies, alertes) seront effacés. '
          'Cette action est définitive. Un abonnement en cours se résilie dans Google Play.',
          size: 13.5,
        ),
        FilledButton(
          onPressed: () => Navigator.pop(sheet, true),
          style: FilledButton.styleFrom(
            backgroundColor: c.loss,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Supprimer définitivement'),
        ),
        WideButton('Annuler', tone: ButtonTone.ghost, onPressed: () => Navigator.pop(sheet, false)),
      ],
    );
    if (ok != true) return;
    try {
      await state.deleteAccount();
      if (context.mounted) showToast(context, 'Ton compte a été supprimé');
    } on AuthFailure catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
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
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.danger = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData? trailing;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Divided(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: danger ? c.lossText : c.muted),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5, color: danger ? c.lossText : null),
        ),
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
