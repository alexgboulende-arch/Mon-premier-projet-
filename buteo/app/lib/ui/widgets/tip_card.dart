import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../screens/journal_screen.dart';
import 'common.dart';

IconData sportIcon(Sport s) => switch (s) {
  Sport.foot => Icons.sports_soccer_outlined,
  Sport.basket => Icons.sports_basketball_outlined,
  Sport.tennis => Icons.sports_tennis_outlined,
};

/// Partage un prono (WhatsApp, Telegram, SMS…).
Future<void> shareTip(Tip t, String rubricName) => SharePlus.instance.share(
  ShareParams(
    subject: 'Prono Buteo',
    text:
        'Buteo · $rubricName\n'
        '${t.fixture.home} – ${t.fixture.away} (${t.time} GMT)\n'
        'Prono : ${t.label} · cote ${odds(t.odds)}\n'
        "Confiance de l'IA : ${t.confidence} %\n"
        '18+ · Joue avec modération',
  ),
);

class TipCard extends StatelessWidget {
  const TipCard({super.key, required this.tip, required this.status, this.rubricName});

  final Tip tip;
  final TipStatus status;

  /// Si renseigné, affiche le bouton de partage.
  final String? rubricName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = tip.fixture;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MatchHeader(
            fixture: f,
            trailing: Text(
              tip.time,
              style: numStyle(16, color: c.fg, weight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Teams(fixture: f, status: status),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: PickChip(tip.label)),
                ),
                const SizedBox(width: 10),
                OddsBox(tip.odds),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            padding: EdgeInsets.fromLTRB(14, 8, rubricName == null ? 14 : 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(child: ConfidenceMeter(tip.confidence)),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(status),
                if (rubricName != null) ...[
                  IconButton(
                    tooltip: 'Ajouter au journal',
                    onPressed: () => showJournalEntrySheet(
                      context,
                      label: '${tip.fixture.home} – ${tip.fixture.away} · ${tip.label}',
                      odds: tip.odds,
                    ),
                    icon: Icon(Icons.menu_book_outlined, size: 20, color: c.muted),
                  ),
                  IconButton(
                    tooltip: 'Partager',
                    onPressed: () => shareTip(tip, rubricName!),
                    icon: Icon(Icons.share_outlined, size: 20, color: c.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchHeader extends StatelessWidget {
  const MatchHeader({super.key, required this.fixture, required this.trailing});

  final Fixture fixture;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surface2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(sportIcon(fixture.sport), size: 15, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${fixture.country} · ${fixture.league}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class Teams extends StatelessWidget {
  const Teams({super.key, required this.fixture, required this.status});

  final Fixture fixture;
  final TipStatus status;

  @override
  Widget build(BuildContext context) {
    const team = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25);
    return Row(
      children: [
        Expanded(child: Text(fixture.home, style: team)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: ScoreView(status)),
        Expanded(
          child: Text(fixture.away, style: team, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class ScoreView extends StatelessWidget {
  const ScoreView(this.status, {super.key});

  final TipStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!status.hasScore) {
      return Text('VS', style: numStyle(16, color: c.faint).copyWith(letterSpacing: 1.2));
    }
    final color = status.kind == StatusKind.live ? c.liveText : c.fg;
    return Semantics(
      label: 'Score ${status.home} à ${status.away}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${status.home}', style: numStyle(30, color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text('–', style: numStyle(22, color: c.faint)),
          ),
          Text('${status.away}', style: numStyle(30, color: color)),
        ],
      ),
    );
  }
}

class PickChip extends StatelessWidget {
  const PickChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
    );
  }
}

class ComboCard extends StatelessWidget {
  const ComboCard({super.key, required this.combo, required this.date, required this.now});

  final Combo combo;
  final DateTime date;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = comboStatus(combo, date, now);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avec un grand texte (réglage d'accessibilité), « cote totale » passe à la ligne.
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(odds(combo.odds), style: numStyle(38)),
                          const MutedText('cote totale', size: 12),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(status),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MutedText(plural(combo.legs.length, 'match')),
                    ConfidenceMeter(combo.confidence),
                    if (combo.odds >= 10)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.lossSoft, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          'Risque élevé',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.lossText),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          for (final leg in combo.legs) _Leg(tip: leg, status: statusOf(leg, date, now)),
        ],
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.tip, required this.status});

  final Tip tip;
  final TipStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = tip.fixture;
    final score = status.hasScore ? '  (${status.home}-${status.away})' : '';
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              tip.time,
              style: numStyle(16, color: c.muted, weight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: '${f.home} – ${f.away}',
                    children: [
                      TextSpan(
                        text: score,
                        style: TextStyle(color: c.muted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                MutedText('${tip.label} · ${f.country}', size: 12.5),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(odds(tip.odds), style: numStyle(18)),
              const SizedBox(height: 4),
              StatusPill(status, small: true),
            ],
          ),
        ],
      ),
    );
  }
}
