import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/rubric_tile.dart';
import '../widgets/match_pick_card.dart';

/// Matchs en cours parmi les pronos du jour, et accès aux pronos live.
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final repo = AppScope.repo(context);
    final now = repo.now();
    final today = dayOf(now);

    final seen = <String>{};
    final live = <(Tip, TipStatus, Rubric)>[];
    for (final r in rubrics) {
      for (final t in repo.day(r, today).allTips) {
        final s = statusOf(t, today, now);
        if (s.kind != StatusKind.live || !seen.add('${t.fixture.home}|${t.fixture.away}')) continue;
        live.add((t, s, r));
      }
    }
    live.sort((a, b) => a.$1.kickoff.compareTo(b.$1.kickoff));
    final liveRubric = rubricsById['live']!;
    final open = state.canSee(liveRubric, today);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        const DemoBanner(),
        const SizedBox(height: 18),
        SectionHeader(
          'Matchs en cours',
          trailing: MutedText('${plural(live.length, 'match')} · ${clock(now.hour * 60 + now.minute)} GMT'),
        ),
        const SizedBox(height: 12),
        if (live.isEmpty)
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: const MutedText(
              "Aucun match en cours pour l'instant. Les matchs du jour commencent à 13:00 GMT.",
              align: TextAlign.center,
            ),
          )
        else
          for (final (t, s, r) in live) ...[
            MatchPickCard(tip: t, status: s, rubric: r, visible: state.canSee(r, today)),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 14),
        const SectionHeader('Pronos live', trailing: TierBadge(Tier.elite)),
        const SizedBox(height: 12),
        const Note(
          "L'IA suit les matchs en direct et publie un prono quand une occasion apparaît. "
          'Une alerte part à chaque nouveau prono.',
          icon: Icons.bolt_rounded,
        ),
        const SizedBox(height: 12),
        WideButton(
          open ? 'Voir les pronos live' : 'Débloquer les pronos live',
          tone: open ? ButtonTone.ghost : ButtonTone.gold,
          onPressed: () => openRubric(context, liveRubric),
        ),
      ],
    );
  }
}
