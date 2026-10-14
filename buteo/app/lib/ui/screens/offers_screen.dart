import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/rubric_tile.dart';
import '../widgets/sheets.dart';

/// Formules Pro et Élite, et coupon à l'unité.
class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final today = dayOf(AppScope.repo(context).now());
    final months = state.planMonths;
    final pro = plans[1];

    String? saving(int m) {
      if (m == 1) return null;
      final full = pro.prices[1]!.fcfa * m;
      return '−${((1 - pro.prices[m]!.fcfa / full) * 100).round()} %';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Segmented<int>(
          options: [
            for (final m in const [1, 3, 6]) (m, '$m mois', saving(m)),
          ],
          value: months,
          onChanged: state.setPlanMonths,
        ),
        const SizedBox(height: 14),
        for (final p in plans) ...[_PlanCard(plan: p, months: months), const SizedBox(height: 12)],
        const SizedBox(height: 4),
        Panel(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Juste un coupon ?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  MutedText('${fcfa(couponPrice.fcfa)} ≈ ${euros(couponPrice.euros)}'),
                ],
              ),
              const SizedBox(height: 6),
              const MutedText('Débloque une seule rubrique VIP pour la journée, sans abonnement.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final r in vipRubrics) _CouponChip(rubric: r, unlocked: state.canSee(r, today))],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MutedText(
          "Les abonnements se renouvellent automatiquement. Tu peux annuler à tout moment dans Google Play, "
          "et tu gardes l'accès jusqu'à la fin de la période payée.",
          size: 12,
        ),
        const SizedBox(height: 6),
        if (state.demoMode)
          Text(
            'Simulation : aucun paiement réel en démonstration.',
            style: TextStyle(fontSize: 12, color: c.goldText, fontWeight: FontWeight.w600),
          )
        else if (state.signedIn && state.billing.available)
          Center(
            child: TextButton(
              onPressed: () {
                state.restorePurchases();
                showToast(context, 'Recherche de tes achats Google Play…');
              },
              child: Text(
                'Restaurer mes achats',
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.months});

  final Plan plan;
  final int months;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final price = plan.prices[months];
    final current = state.tier == plan.tier;
    final included = !current && state.tier.includes(plan.tier);

    Widget? action;
    if (current) {
      action = _Status('Ta formule actuelle');
    } else if (included && plan.tier != Tier.free) {
      action = _Status('Inclus dans ta formule ${state.tier.label}');
    } else if (plan.tier != Tier.free) {
      action = WideButton(
        'Choisir ${plan.tier.label}',
        tone: plan.tier == Tier.pro ? ButtonTone.gold : ButtonTone.green,
        onPressed: () => showPlanSheet(context, plan),
      );
    }

    return Panel(
      radius: 18,
      borderColor: plan.tier == Tier.pro ? c.gold.withValues(alpha: .6) : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.tier.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              if (plan.tag != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    plan.tag!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.goldText),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(price == null ? '0 FCFA' : fcfa(price.fcfa), style: numStyle(34)),
              MutedText(
                price == null
                    ? 'pour toujours'
                    : '≈ ${euros(price.euros)} · ${months == 1 ? 'par mois' : 'soit ${fcfa((price.fcfa / months / 100).round() * 100)} / mois'}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in plan.perks) Padding(padding: const EdgeInsets.only(bottom: 7), child: Note(p)),
          if (action != null) ...[const SizedBox(height: 6), action],
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.winText),
      ),
    );
  }
}

class _CouponChip extends StatelessWidget {
  const _CouponChip({required this.rubric, required this.unlocked});

  final Rubric rubric;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ActionChip(
      onPressed: () => unlocked ? openRubric(context, rubric) : showUnlockSheet(context, rubric),
      avatar: Icon(unlocked ? Icons.check_rounded : rubric.icon, size: 16, color: unlocked ? c.winText : c.fg),
      label: Text(rubric.name),
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: unlocked ? c.winText : c.fg),
      backgroundColor: c.surface2,
      side: BorderSide(color: unlocked ? c.winText.withValues(alpha: .4) : c.line),
      shape: const StadiumBorder(),
    );
  }
}
