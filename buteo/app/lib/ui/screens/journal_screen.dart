import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/journal.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/sheets.dart';

void openJournal(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const JournalScreen()));
}

/// Montant signé : « +1 250 FCFA », « −500 FCFA ».
String signedFcfa(int n) => '${n > 0 ? '+' : (n < 0 ? '−' : '')}${fmt.fcfa(n.abs())}';

/// Journal de paris : bilan, liste et saisie.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

enum _Filter { all, pending, settled }

class _JournalScreenState extends State<JournalScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final journal = AppScope.of(context).journal;
    return ListenableBuilder(
      listenable: journal,
      builder: (context, _) {
        final all = journal.entries;
        final shown = switch (_filter) {
          _Filter.all => all,
          _Filter.pending => all.where((e) => e.status == BetStatus.pending).toList(),
          _Filter.settled => all.where((e) => e.status != BetStatus.pending).toList(),
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Journal de paris')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showJournalEntrySheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Nouveau pari'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              _Summary(stats: journal.stats),
              const SizedBox(height: 16),
              Segmented<_Filter>(
                options: const [
                  (_Filter.all, 'Tous', null),
                  (_Filter.pending, 'En cours', null),
                  (_Filter.settled, 'Terminés', null),
                ],
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Panel(
                  padding: const EdgeInsets.all(16),
                  child: MutedText(
                    all.isEmpty
                        ? 'Note ici tes paris pour suivre tes gains et tes pertes. '
                              'Tu peux aussi ajouter un prono Buteo avec le bouton « Journal » de sa carte.'
                        : 'Aucun pari dans cette liste.',
                    size: 13,
                  ),
                )
              else
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [for (final e in shown) _EntryTile(entry: e)]),
                ),
              const SizedBox(height: 22),
              const ResponsibleNote(),
            ],
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats});

  final JournalStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profitColor = stats.profit > 0 ? c.winText : (stats.profit < 0 ? c.lossText : c.fg);
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MutedText('Bénéfice', size: 12),
          Text(signedFcfa(stats.profit), style: numStyle(30, color: profitColor)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Figure('Rendement', stats.roi == null ? '—' : fmt.percent(stats.roi!, signed: true))),
              Expanded(child: _Figure('Réussite', stats.successRate == null ? '—' : fmt.percent(stats.successRate!))),
              Expanded(child: _Figure('Misé', fmt.fcfa(stats.staked))),
            ],
          ),
          const SizedBox(height: 8),
          MutedText(
            '${stats.settled} pari${stats.settled > 1 ? 's' : ''} terminé${stats.settled > 1 ? 's' : ''}'
            '${stats.pending > 0 ? ' · ${stats.pending} en cours' : ''}',
            size: 12,
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MutedText(label, size: 12),
      FittedBox(
        child: Text(value, style: numStyle(18, color: context.colors.fg)),
      ),
    ],
  );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (entry.status) {
      BetStatus.won => (c.winText, c.winSoft),
      BetStatus.lost => (c.lossText, c.lossSoft),
      BetStatus.pending => (c.liveText, c.liveSoft),
      BetStatus.refunded => (c.muted, c.surface2),
    };
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => showJournalEntrySheet(context, entry: entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    MutedText(
                      '${fmt.shortDate(entry.day)} · cote ${fmt.odds(entry.odds)} · mise ${fmt.fcfa(entry.stake)}',
                      size: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      entry.status.label,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
                    ),
                  ),
                  if (entry.settled) ...[
                    const SizedBox(height: 4),
                    Text(signedFcfa(entry.profit), style: numStyle(15, color: fg)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nouveau pari (éventuellement prérempli depuis un prono), ou modification d'un pari existant.
Future<void> showJournalEntrySheet(BuildContext context, {JournalEntry? entry, String? label, double? odds}) {
  return showButeoSheet(context, (sheet) => [_EntryForm(entry: entry, label: label, odds: odds)]);
}

class _EntryForm extends StatefulWidget {
  const _EntryForm({this.entry, this.label, this.odds});

  final JournalEntry? entry;
  final String? label;
  final double? odds;

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  late final _label = TextEditingController(text: widget.entry?.label ?? widget.label ?? '');
  late final _odds = TextEditingController(text: _initialOdds());
  late final _stake = TextEditingController(text: widget.entry?.stake.toString() ?? '');
  late BetStatus _status = widget.entry?.status ?? BetStatus.pending;
  String? _error;

  String _initialOdds() {
    final v = widget.entry?.odds ?? widget.odds;
    return v == null ? '' : fmt.odds(v);
  }

  @override
  void dispose() {
    _label.dispose();
    _odds.dispose();
    _stake.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final odds = double.tryParse(_odds.text.trim().replaceAll(',', '.'));
    final stake = int.tryParse(_stake.text.replaceAll(RegExp(r'\s'), ''));
    if (label.isEmpty || label.length > 120) {
      setState(() => _error = 'Décris le pari (120 caractères au plus).');
      return;
    }
    if (odds == null || odds < 1.01 || odds > 1000) {
      setState(() => _error = 'Cote invalide (par exemple 1,85).');
      return;
    }
    if (stake == null || stake <= 0 || stake > 10000000) {
      setState(() => _error = 'Mise invalide (en FCFA).');
      return;
    }
    final journal = AppScope.read(context).journal;
    final navigator = Navigator.of(context);
    final existing = widget.entry;
    if (existing == null) {
      final added = await journal.add(label: label, odds: odds, stake: stake);
      if (_status != BetStatus.pending) await journal.update(added.copyWith(status: _status));
    } else {
      await journal.update(existing.copyWith(label: label, odds: odds, stake: stake, status: _status));
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final existing = widget.entry;
    // Le clavier ne doit pas cacher les champs.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            existing == null ? 'Nouveau pari' : 'Modifier le pari',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Pari', hintText: 'Ex. : Benfica – Celtic · Victoire Benfica'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _odds,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(labelText: 'Cote'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _stake,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Mise', suffixText: 'FCFA'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const MutedText('Résultat', size: 12),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in BetStatus.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.lossText, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          WideButton('Enregistrer', onPressed: _save),
          if (existing != null) ...[
            const SizedBox(height: 8),
            WideButton(
              'Supprimer ce pari',
              tone: ButtonTone.ghost,
              onPressed: () async {
                final navigator = Navigator.of(context);
                await AppScope.read(context).journal.remove(existing.id);
                navigator.pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}
