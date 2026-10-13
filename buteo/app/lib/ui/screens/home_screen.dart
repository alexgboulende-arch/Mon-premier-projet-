import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/rubric_tile.dart';
import '../widgets/tip_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final repo = AppScope.repo(context);
    final now = repo.now();
    final today = dayOf(now);
    final toDrop = 24 * 60 - (now.hour * 60 + now.minute);
    final selection = rubricsById['selection']!;
    final top = [...repo.day(selection, today).tips]..sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = top.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        const DemoBanner(),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Pronos du jour'),
                  const SizedBox(height: 2),
                  Text(
                    longDate(today),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.4),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const MutedText('Prochains pronos à 00:00', size: 12),
                Text('dans ${hoursMinutes(toDrop)}', style: numStyle(20, color: c.fg)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: () => openRubric(context, selection),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 15, color: c.winText),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    "Prono phare · la confiance la plus haute de l'IA",
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.winText),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        TipCard(tip: best, status: statusOf(best, today, now), rubricName: selection.name),
        if (state.showAds) ...[const SizedBox(height: 22), const AdSlot()],
        const SizedBox(height: 26),
        SectionHeader('Gratuit', trailing: MutedText('${freeRubrics.length} rubriques')),
        const SizedBox(height: 12),
        RubricGrid(freeRubrics),
        const SizedBox(height: 26),
        SectionHeader(
          'VIP',
          trailing: state.tier == Tier.elite
              ? const MutedText('Tout est débloqué')
              : InkWell(
                  onTap: () => state.setTab(3),
                  child: Text(
                    'Voir les offres',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.goldText),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        RubricGrid(vipRubrics),
        const SizedBox(height: 22),
        const ResponsibleNote(),
      ],
    );
  }
}
