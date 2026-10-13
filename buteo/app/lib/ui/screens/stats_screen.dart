import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/rubric_tile.dart';

/// Résultats publics : tous les pronos sont comptés, gagnés comme perdus.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final repo = AppScope.repo(context);
    final days = state.statsDays;
    final g = globalStats(repo, days);
    final today = dayOf(repo.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        const DemoBanner(),
        const SizedBox(height: 14),
        Segmented<int>(
          options: const [(7, '7 derniers jours', null), (30, '30 derniers jours', null)],
          value: days,
          onChanged: state.setStatsDays,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _Kpi('Réussite', percent(g.rate)),
            const SizedBox(width: 10),
            _Kpi('Pronos', '${g.count}'),
            const SizedBox(width: 10),
            _Kpi('Rendement', percent(g.roi, signed: true), g.roi >= 0 ? c.winText : c.lossText),
          ],
        ),
        const SizedBox(height: 14),
        _DailyChart(repo: repo, today: today),
        const SizedBox(height: 22),
        const SectionHeader('Par rubrique'),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              const _Row(header: true, cells: ['Rubrique', 'Gagnés', 'Réussite', 'Rendement']),
              for (final r in rubrics) _RubricRow(rubric: r, stats: statsFor(repo, r, days)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Note(
          'Tous les pronos sont comptés, gagnés comme perdus. Le rendement indique ce que tu aurais '
          'gagné ou perdu en misant la même somme sur chaque prono.',
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, [this.color]);

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Panel(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText(label, size: 11.5),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(value, style: numStyle(30, color: color ?? context.colors.fg)),
          ),
        ],
      ),
    ),
  );
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.repo, required this.today});

  final TipsRepository repo;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dates = [for (var d = 14; d >= 1; d--) today.subtract(Duration(days: d))];
    final rates = [for (final d in dates) dayRate(repo, d)];
    const h = 130.0;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Réussite par jour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const MutedText('14 derniers jours'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                height: h,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final v in ['100 %', '50 %', '0 %'])
                      Text(v, style: TextStyle(fontSize: 10.5, color: c.faint, height: 1)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: h,
                  child: Stack(
                    children: [
                      for (final y in [0.0, h / 2])
                        Positioned(
                          top: y,
                          left: 0,
                          right: 0,
                          child: Container(height: 1, color: c.line),
                        ),
                      Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 1, color: c.line)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < rates.length; i++)
                            Expanded(
                              child: Semantics(
                                label: '${shortDate(dates[i])} : ${percent(rates[i])}',
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  height: (rates[i] * h).clamp(3, h),
                                  decoration: BoxDecoration(
                                    color: rates[i] < .5 ? c.loss : c.win,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Row(
              children: [
                for (final d in dates)
                  Expanded(
                    child: Text(
                      '${d.day}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: c.faint),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              _Legend(color: c.win, label: '50 % ou plus'),
              _Legend(color: c.loss, label: 'Moins de 50 %'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 5),
      MutedText(label, size: 11.5),
    ],
  );
}

class _RubricRow extends StatelessWidget {
  const _RubricRow({required this.rubric, required this.stats});

  final Rubric rubric;
  final PickStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () => openRubric(context, rubric),
      child: _Row(
        cells: [rubric.name, '${stats.won}/${stats.count}', percent(stats.rate), percent(stats.roi, signed: true)],
        tier: rubric.isVip ? rubric.tier : null,
        lastColor: stats.roi >= 0 ? c.winText : c.lossText,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.header = false, this.tier, this.lastColor});

  final List<String> cells;
  final bool header;
  final Tier? tier;
  final Color? lastColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    TextStyle num([Color? color]) => header
        ? TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .8, color: c.muted)
        : numStyle(16, color: color ?? c.fg, weight: FontWeight.w600);
    Widget right(String t, double w, [Color? color]) => SizedBox(
      width: w,
      child: Text(header ? t.toUpperCase() : t, textAlign: TextAlign.right, style: num(color)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: header
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: header
                ? Text(cells[0].toUpperCase(), style: num())
                : Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(cells[0], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      if (tier != null) TierBadge(tier!),
                    ],
                  ),
          ),
          right(cells[1], 50),
          right(cells[2], 64),
          right(cells[3], 78, lastColor),
        ],
      ),
    );
  }
}
