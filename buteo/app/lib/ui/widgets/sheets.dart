import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/tips_repository.dart';
import '../../services/billing_service.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../screens/login.dart';
import 'common.dart';

/// Fenêtre du bas d'écran, défilante si le contenu est long.
Future<T?> showButeoSheet<T>(BuildContext context, List<Widget> Function(BuildContext sheet) children) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, w) in children(sheetContext).indexed) ...[if (i > 0) const SizedBox(height: 14), w],
          ],
        ),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800));
}

class _PayBox extends StatelessWidget {
  const _PayBox({required this.caption, required this.price, this.playKey});

  final String caption;
  final Price price;

  /// Produit Google Play : son prix local remplace le prix indicatif s'il est connu.
  final String? playKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MutedText(caption),
                Text(AppScope.of(context).playPrices[playKey] ?? fcfa(price.fcfa), style: numStyle(28)),
              ],
            ),
          ),
          MutedText('≈ ${euros(price.euros)}\nvia Google Play', align: TextAlign.right),
        ],
      ),
    );
  }
}

/// Achat d'un coupon : une rubrique VIP débloquée pour la journée.
Future<void> showUnlockSheet(BuildContext context, Rubric rubric) {
  final state = AppScope.read(context);
  final today = dayOf(AppScope.repo(context).now());
  return showButeoSheet(
    context,
    (sheet) => [
      _SheetTitle('Débloquer « ${rubric.name} »'),
      MutedText(
        "Accès à tous les pronos de cette rubrique pour aujourd'hui, ${longDate(today).toLowerCase()}.",
        size: 13.5,
      ),
      const _PayBox(caption: 'Coupon du jour', price: couponPrice, playKey: PlayProducts.coupon),
      WideButton(
        'Payer ${state.playPrices[PlayProducts.coupon] ?? fcfa(couponPrice.fcfa)}',
        tone: ButtonTone.gold,
        onPressed: () {
          if (!state.demoMode) return _payWithPlay(context, sheet, () => state.buyCoupon(rubric));
          state.unlock(rubric, today);
          Navigator.pop(sheet);
          showToast(context, "« ${rubric.name} » débloqué pour aujourd'hui");
        },
      ),
      WideButton('Annuler', tone: ButtonTone.ghost, onPressed: () => Navigator.pop(sheet)),
      MutedText(_paymentNote(state), size: 12),
    ],
  );
}

/// Souscription à une formule Pro ou Élite.
Future<void> showPlanSheet(BuildContext context, Plan plan) {
  final state = AppScope.read(context);
  final months = state.planMonths;
  final price = plan.prices[months]!;
  return showButeoSheet(
    context,
    (sheet) => [
      _SheetTitle('Passer ${plan.tier.label} · $months mois'),
      for (final p in plan.perks) Note(p),
      _PayBox(
        caption: 'Total',
        price: price,
        playKey: '${PlayProducts.subscriptionFor(plan.tier)}/${PlayProducts.basePlans[months]}',
      ),
      WideButton(
        "S'abonner",
        tone: plan.tier == Tier.pro ? ButtonTone.gold : ButtonTone.green,
        onPressed: () {
          if (!state.demoMode) {
            return _payWithPlay(context, sheet, () => state.buySubscription(plan.tier, months));
          }
          state.setTier(plan.tier);
          Navigator.pop(sheet);
          showToast(context, 'Bienvenue dans la formule ${plan.tier.label}');
        },
      ),
      WideButton('Annuler', tone: ButtonTone.ghost, onPressed: () => Navigator.pop(sheet)),
      MutedText(
        'Renouvellement automatique, annulable à tout moment dans Google Play. ${_paymentNote(state)}',
        size: 12,
      ),
    ],
  );
}

/// Dernières notifications : publication de minuit et résultats de la Sélection du jour.
Future<void> showNotificationsSheet(BuildContext context) {
  final repo = AppScope.repo(context);
  final now = repo.now();
  final today = dayOf(now);
  final selection = rubricsById['selection']!;
  final done = repo
      .day(selection, today)
      .tips
      .map((t) => (t, statusOf(t, today, now)))
      .where((e) => e.$2.finished)
      .toList();
  return showButeoSheet(
    context,
    (sheet) => [
      const _SheetTitle('Notifications'),
      _NotifRow(
        time: '00:00',
        title: 'Les pronos du ${dayMonth(today)} sont en ligne',
        detail: '${rubrics.length} rubriques mises à jour',
      ),
      for (final (t, s) in done)
        _NotifRow(
          time: clock(t.kickoff + matchDuration[t.fixture.sport]!),
          title: 'Sélection du jour : ${s.kind == StatusKind.won ? 'gagné' : 'perdu'}',
          detail: '${t.fixture.home} – ${t.fixture.away} · ${t.label} · cote ${odds(t.odds)}',
        ),
      WideButton('Fermer', tone: ButtonTone.ghost, onPressed: () => Navigator.pop(sheet)),
    ],
  );
}

class _NotifRow extends StatelessWidget {
  const _NotifRow({required this.time, required this.title, required this.detail});

  final String time;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              time,
              style: numStyle(16, color: c.muted, weight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                MutedText(detail, size: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _paymentNote(AppState state) =>
    state.demoMode ? 'Simulation : aucun paiement réel en démonstration.' : 'Paiement sécurisé par Google Play.';

/// Achat réel : il faut un compte (l'achat y est rattaché) et Google Play.
/// Google interdit de proposer un autre moyen de paiement dans l'app.
void _payWithPlay(BuildContext context, BuildContext sheet, Future<void> Function() buy) {
  final state = AppScope.read(context);
  Navigator.pop(sheet);
  if (!state.signedIn) {
    showToast(context, 'Connecte-toi d’abord : ton achat sera rattaché à ton compte.');
    showLoginSheet(context);
    return;
  }
  if (!state.billing.available) {
    showToast(context, 'Le paiement passe par Google Play : installe Buteo depuis le Play Store.');
    return;
  }
  buy();
}
