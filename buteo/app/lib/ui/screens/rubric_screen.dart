import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/catalog.dart';

import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import '../widgets/tip_card.dart';

/// Pronos d'une rubrique : ceux du jour et l'historique des 7 derniers jours.
class RubricScreen extends StatefulWidget {
  const RubricScreen({super.key, required this.rubric});

  final Rubric rubric;

  @override
  State<RubricScreen> createState() => _RubricScreenState();
}

class _RubricScreenState extends State<RubricScreen> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final rubric = widget.rubric;
    final state = AppScope.of(context);
    final repo = AppScope.repo(context);
    final now = repo.now();
    final today = dayOf(now);
    final stats = statsFor(repo, rubric, 30);

    final children = <Widget>[
      Segmented<bool>(
        options: const [(false, "Aujourd'hui", null), (true, 'Historique', null)],
        value: _history,
        onChanged: (v) => setState(() => _history = v),
      ),
      _StatsStrip(stats),
      if (_history) ..._historyList(repo, rubric, today, now) else ..._todayList(state, repo, rubric, today, now),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(rubric.name),
        actions: [if (rubric.isVip) Padding(padding: const EdgeInsets.only(right: 16), child: TierBadge(rubric.tier))],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }

  List<Widget> _todayList(AppState state, TipsRepository repo, Rubric rubric, DateTime today, DateTime now) {
    if (!repo.isDemo && !rubric.engine) return const [_Soon()];
    final locked = !state.canSee(rubric, today) || repo.isLocked(rubric, today);
    // Rubrique verrouillée : aperçu flou de pronos fictifs (les vrais ne sont pas chargés).
    final day = locked && !repo.isDemo ? _preview.day(rubric, today) : repo.day(rubric, today);
    final cards = <Widget>[
      if (day.isCombo)
        ComboCard(combo: day.combo!, date: today, now: now)
      else
        for (final t in day.tips)
          TipCard(tip: t, status: statusOf(t, today, now), rubricName: locked ? null : rubric.name),
    ];
    if (!rubric.isVip && state.showAds && cards.length > 2) cards.insert(2, const AdSlot());

    if (locked) return [_Locked(rubric: rubric, preview: cards)];
    if (cards.isEmpty) {
      return const [
        _Empty(
          'Pas encore de prono dans cette rubrique aujourd’hui. '
          'Les pronos sont publiés chaque nuit à 00:00 GMT.',
        ),
      ];
    }
    return [
      const Note(
        "Pronos générés par l'IA Buteo. L'indice de confiance est la probabilité estimée que le prono passe.",
        icon: Icons.auto_awesome_outlined,
      ),
      ...cards,
    ];
  }

  List<Widget> _historyList(TipsRepository repo, Rubric rubric, DateTime today, DateTime now) {
    if (!repo.isDemo && !rubric.engine) return const [_Soon()];
    final out = <Widget>[
      const Note("Tous les pronos sont affichés, gagnés comme perdus. L'historique VIP est public."),
    ];
    for (var d = 1; d <= 7; d++) {
      final date = today.subtract(Duration(days: d));
      final day = repo.day(rubric, date);
      if (day.picks.isEmpty) continue;
      final won = day.picks.where((p) => p.won).length;
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(shortDate(date), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              MutedText('$won/${day.picks.length} ${won > 1 ? 'gagnés' : 'gagné'}'),
            ],
          ),
        ),
      );
      if (day.isCombo) {
        out.add(ComboCard(combo: day.combo!, date: date, now: now));
      } else {
        out.addAll(day.tips.map((t) => TipCard(tip: t, status: statusOf(t, date, now))));
      }
    }
    if (out.length == 1) out.add(const _Empty('L’historique se remplit jour après jour, dès les premiers résultats.'));
    return out;
  }
}

/// Pronos fictifs, uniquement pour l'aperçu flou des rubriques verrouillées.
final _preview = DemoTipsRepository();

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    child: MutedText(text, align: TextAlign.center, size: 13),
  );
}

class _Soon extends StatelessWidget {
  const _Soon();

  @override
  Widget build(BuildContext context) => const _Empty(
    'Cette rubrique arrive bientôt : l’IA Buteo couvre pour l’instant le football. '
    'Basket, tennis et pronos en direct suivront.',
  );
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip(this.s);

  final PickStats s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String label, String value, [Color? color]) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MutedText(label, size: 11),
            const SizedBox(height: 2),
            Text(value, style: numStyle(22, color: color ?? c.fg)),
          ],
        ),
      ),
    );
    return Panel(
      radius: 14,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell('Réussite 30 j', percent(s.rate)),
            VerticalDivider(width: 1, color: c.line),
            cell('Cote moyenne', odds(s.averageOdds)),
            VerticalDivider(width: 1, color: c.line),
            cell('Rendement', percent(s.roi, signed: true), s.roi >= 0 ? c.winText : c.lossText),
          ],
        ),
      ),
    );
  }
}

/// Aperçu flou des pronos VIP, avec les deux façons de les débloquer.
class _Locked extends StatelessWidget {
  const _Locked({required this.rubric, required this.preview});

  final Rubric rubric;
  final List<Widget> preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(
              opacity: .5,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Column(
                  children: [for (final w in preview) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 0),
          child: Panel(
            radius: 18,
            borderColor: c.gold.withValues(alpha: .6),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.lock_outline_rounded, color: c.goldText),
                ),
                const SizedBox(height: 12),
                Text(
                  'Rubrique ${rubric.tier.label}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const MutedText(
                  "Débloque les pronos d'aujourd'hui pour cette rubrique, ou abonne-toi pour tout voir chaque jour.",
                  size: 13,
                  align: TextAlign.center,
                ),
                const SizedBox(height: 14),
                WideButton(
                  'Débloquer ce coupon · ${fcfa(couponPrice.fcfa)}',
                  tone: ButtonTone.gold,
                  onPressed: () => showUnlockSheet(context, rubric),
                ),
                const SizedBox(height: 10),
                WideButton('Voir les abonnements', tone: ButtonTone.ghost, onPressed: () => goToOffers(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
