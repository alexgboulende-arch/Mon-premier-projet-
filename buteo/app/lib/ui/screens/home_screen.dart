import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/match_pick_card.dart';
import '../widgets/rubric_tile.dart';
import '../widgets/tip_card.dart';
import 'favorites_screen.dart';

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
    final best = top.firstOrNull;

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
        if (best == null)
          Panel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.nightlight_round, color: c.winText),
                const SizedBox(width: 12),
                const Expanded(
                  child: MutedText(
                    'Les pronos du jour ne sont pas encore publiés. L’IA Buteo les met en ligne chaque nuit à 00:00 GMT.',
                    size: 13,
                  ),
                ),
              ],
            ),
          )
        else ...[
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
        ],
        if (state.showAds) ...[const SizedBox(height: 22), const AdSlot()],
        const SizedBox(height: 26),
        const _FavoritesSection(),
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

/// Matchs du jour des équipes suivies, toutes rubriques confondues.
class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final repo = AppScope.repo(context);
    final now = repo.now();
    final today = dayOf(now);

    if (state.favoriteCount == 0) {
      return Panel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.star_outline_rounded, color: c.goldText),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Suis tes équipes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  MutedText('Leurs matchs du jour s’afficheront ici.'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => openFavorites(context),
              child: Text(
                'Choisir',
                style: TextStyle(color: c.goldText, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    // Un match peut apparaître dans plusieurs rubriques : on garde celle que
    // l'utilisateur peut voir, sinon la première.
    final byMatch = <String, (Tip, Rubric)>{};
    for (final r in rubrics) {
      for (final t in repo.day(r, today).allTips) {
        if (!state.followsFixture(t.fixture)) continue;
        final key = '${t.fixture.sport.name}|${t.fixture.home}|${t.fixture.away}';
        final known = byMatch[key];
        if (known == null || (!state.canSee(known.$2, today) && state.canSee(r, today))) byMatch[key] = (t, r);
      }
    }
    final matches = byMatch.values.toList()..sort((a, b) => a.$1.kickoff.compareTo(b.$1.kickoff));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Mes équipes',
          trailing: InkWell(
            onTap: () => openFavorites(context),
            child: Text(
              'Modifier',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.goldText),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: MutedText(
              'Pas de prono sur tes ${state.favoriteCount} équipe${state.favoriteCount > 1 ? 's' : ''} aujourd’hui.',
              align: TextAlign.center,
            ),
          )
        else
          for (final (i, (t, r)) in matches.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            MatchPickCard(
              tip: t,
              status: statusOf(t, today, now),
              rubric: r,
              visible: state.canSee(r, today),
              showTime: true,
            ),
          ],
      ],
    );
  }
}
