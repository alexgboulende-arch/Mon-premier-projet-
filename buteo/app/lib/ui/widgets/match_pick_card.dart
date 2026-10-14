import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import 'common.dart';
import 'rubric_tile.dart';
import 'tip_card.dart';

/// Un match et le prono d'une rubrique, masqué si la rubrique est verrouillée.
/// Sert pour les matchs en direct et pour les équipes favorites.
class MatchPickCard extends StatelessWidget {
  const MatchPickCard({
    super.key,
    required this.tip,
    required this.status,
    required this.rubric,
    required this.visible,
    this.showTime = false,
  });

  final Tip tip;
  final TipStatus status;
  final Rubric rubric;
  final bool visible;

  /// Affiche l'heure du match à côté de l'état (utile avant le coup d'envoi).
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MatchHeader(
            fixture: tip.fixture,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showTime && status.kind == StatusKind.soon) ...[
                  Text(
                    tip.time,
                    style: numStyle(16, color: c.fg, weight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                ],
                StatusPill(status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Teams(fixture: tip.fixture, status: status),
          ),
          InkWell(
            onTap: () => openRubric(context, rubric),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Icon(rubric.icon, size: 15, color: c.muted),
                  const SizedBox(width: 8),
                  MutedText('${rubric.name} :'),
                  const SizedBox(width: 6),
                  Expanded(
                    child: visible
                        ? Text(
                            '${tip.label} · cote ${odds(tip.odds)}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          )
                        : Align(alignment: Alignment.centerLeft, child: TierBadge(rubric.tier, locked: true)),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
