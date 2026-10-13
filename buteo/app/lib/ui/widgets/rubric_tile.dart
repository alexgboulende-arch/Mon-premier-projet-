import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../screens/rubric_screen.dart';
import 'common.dart';

class RubricTile extends StatelessWidget {
  const RubricTile(this.rubric, {super.key});

  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final repo = AppScope.repo(context);
    final now = repo.now();
    final today = dayOf(now);
    final day = repo.day(rubric, today);
    final String summary;
    if (!repo.isDemo && !rubric.engine) {
      summary = 'Bientôt disponible';
    } else if (!repo.isDemo && (!state.canSee(rubric, today) || repo.isLocked(rubric, today))) {
      summary = 'Pronos du jour réservés';
    } else {
      summary = pickCountLabel(day, day.tips.map((t) => statusOf(t, today, now)).toList());
    }
    final vip = rubric.isVip;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openRubric(context, rubric),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: vip ? c.goldSoft : c.winSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(rubric.icon, size: 21, color: vip ? c.goldText : c.winText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rubric.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                    if (vip) ...[
                      const SizedBox(height: 4),
                      TierBadge(rubric.tier, locked: !state.canSee(rubric, today)),
                    ],
                    const SizedBox(height: 3),
                    Text(summary, style: TextStyle(fontSize: 11.5, color: c.muted, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille de deux colonnes ; une tuile `wide` prend toute la largeur.
class RubricGrid extends StatelessWidget {
  const RubricGrid(this.items, {super.key});

  final List<Rubric> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final pending = <Rubric>[];
    void flush() {
      if (pending.isEmpty) return;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: RubricTile(pending[0])),
              const SizedBox(width: 10),
              Expanded(child: pending.length > 1 ? RubricTile(pending[1]) : const SizedBox()),
            ],
          ),
        ),
      );
      pending.clear();
    }

    for (final r in items) {
      if (r.wide) {
        flush();
        rows.add(RubricTile(r));
      } else {
        pending.add(r);
        if (pending.length == 2) flush();
      }
    }
    flush();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 10), rows[i]],
      ],
    );
  }
}

void openRubric(BuildContext context, Rubric rubric) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RubricScreen(rubric: rubric)));
}
