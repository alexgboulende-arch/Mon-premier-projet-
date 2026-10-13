import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';

/// Le symbole Buteo : œil de rapace avec un ballon comme iris.
class ButeoLogo extends StatelessWidget {
  const ButeoLogo({super.key, this.width = 40});

  final double width;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/logo/buteo-symbole.svg',
    width: width,
    height: width * 370 / 480,
    semanticsLabel: 'Buteo',
  );
}

/// Bloc avec fond, bordure et coins arrondis.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero, this.borderColor, this.radius = 16});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: borderColor ?? c.line),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.2)),
      ),
      ?trailing,
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: context.colors.muted),
  );
}

class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.size = 12.5, this.align});

  final String text;
  final double size;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: TextStyle(fontSize: size, color: context.colors.muted, height: 1.4),
  );
}

/// Petite étiquette « PRO » / « ÉLITE », avec un cadenas si la rubrique est verrouillée.
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.locked = false});

  final Tier tier;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(6)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked) ...[Icon(Icons.lock_outline_rounded, size: 11, color: c.goldInk), const SizedBox(width: 3)],
            Text(
              tier.badge,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: c.goldInk),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.small = false});

  final TipStatus status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color fg, Widget icon, String text) = switch (status.kind) {
      StatusKind.won => (c.winSoft, c.winText, Icon(Icons.check_rounded, size: 14, color: c.winText), 'Gagné'),
      StatusKind.lost => (c.lossSoft, c.lossText, Icon(Icons.close_rounded, size: 14, color: c.lossText), 'Perdu'),
      StatusKind.live => (c.liveSoft, c.liveText, _LiveDot(color: c.liveText), status.label ?? 'En cours'),
      StatusKind.soon => (c.surface2, c.muted, Icon(Icons.schedule_rounded, size: 14, color: c.muted), 'À venir'),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: small ? 11 : 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 1.0, end: .25).animate(_ctrl),
    child: Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}

/// Indice de confiance de l'IA : 10 segments et le pourcentage.
class ConfidenceMeter extends StatelessWidget {
  const ConfidenceMeter(this.confidence, {super.key, this.showLabel = true});

  final int confidence;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = (confidence / 10).round().clamp(1, 10);
    final color = confidence >= 65 ? c.winText : (confidence >= 40 ? c.goldText : c.lossText);
    return Semantics(
      label: 'Confiance $confidence %',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel) ...[MutedText('Confiance', size: 12), const SizedBox(width: 8)],
          for (var i = 1; i <= 10; i++)
            Container(
              width: 6,
              height: 13,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(color: i <= on ? color : c.line, borderRadius: BorderRadius.circular(2)),
            ),
          const SizedBox(width: 6),
          Text('$confidence %', style: numStyle(16, color: c.fg)),
        ],
      ),
    );
  }
}

/// La cote, en vert, comme sur un ticket.
class OddsBox extends StatelessWidget {
  const OddsBox(this.value, {super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 4),
      decoration: BoxDecoration(color: c.win, borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'COTE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: c.winInk.withValues(alpha: .7),
            ),
          ),
          Text(odds(value), style: numStyle(21, color: c.winInk)),
        ],
      ),
    );
  }
}

/// Choix entre quelques options (Aujourd'hui / Historique, 1 / 3 / 6 mois…).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final List<(T, String, String?)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Panel(
      radius: 12,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (v, label, hint) in options)
            Expanded(
              child: Semantics(
                selected: v == value,
                button: true,
                child: Material(
                  color: v == value ? c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onChanged(v),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                      child: Column(
                        children: [
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: v == value ? c.fg : c.muted,
                            ),
                          ),
                          if (hint != null)
                            Text(
                              hint,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.winText),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum ButtonTone { gold, green, ghost }

class WideButton extends StatelessWidget {
  const WideButton(this.label, {super.key, required this.onPressed, this.tone = ButtonTone.green, this.icon});

  final String label;
  final VoidCallback onPressed;
  final ButtonTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      ButtonTone.gold => (c.gold, c.goldInk),
      ButtonTone.green => (c.win, c.winInk),
      ButtonTone.ghost => (c.surface2, c.fg),
    };
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: 18),
        label: Text(label, textAlign: TextAlign.center),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          textStyle: const TextStyle(fontFamily: kFontUi, fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: tone == ButtonTone.ghost ? BorderSide(color: c.line) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Emplacement de la bannière publicitaire (version gratuite).
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.showAds) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.faint),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ANNONCE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.faint),
                ),
                const MutedText('Bannière publicitaire 320 × 50'),
              ],
            ),
          ),
          TextButton(
            onPressed: () => goToOffers(context),
            child: Text(
              'Retirer les pubs',
              style: TextStyle(color: c.goldText, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Revient à l'écran principal et ouvre l'onglet Offres.
void goToOffers(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  AppScope.read(context).setTab(3);
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.icon = Icons.check_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 16, color: context.colors.winText),
      ),
      const SizedBox(width: 8),
      Expanded(child: MutedText(text)),
    ],
  );
}

class ResponsibleNote extends StatelessWidget {
  const ResponsibleNote({super.key});

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 20, color: context.colors.goldText),
        const SizedBox(width: 10),
        const Expanded(
          child: MutedText(
            "18+ uniquement. Les pronostics sont des estimations : aucun gain n'est garanti. "
            'Ne mise que ce que tu peux te permettre de perdre.',
          ),
        ),
      ],
    ),
  );
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: c.muted),
          const SizedBox(width: 8),
          const Expanded(child: MutedText('Version de démonstration · données fictives · heures en GMT', size: 12)),
        ],
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2400)));
}

String pickCountLabel(RubricDay day, List<TipStatus> statuses) {
  if (day.isCombo) return '${plural(day.combo!.legs.length, 'match')} · cote ${odds(day.combo!.odds)}';
  final won = statuses.where((s) => s.kind == StatusKind.won).length;
  final live = statuses.where((s) => s.kind == StatusKind.live).length;
  return [
    plural(day.tips.length, 'prono'),
    if (won > 0) plural(won, 'gagné'),
    if (live > 0) '$live en cours',
  ].join(' · ');
}
