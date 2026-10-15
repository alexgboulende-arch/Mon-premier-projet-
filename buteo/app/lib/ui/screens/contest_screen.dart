import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/contest.dart';
import '../../data/tips_repository.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import 'login.dart';

void openContest(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ContestScreen()));
}

/// Concours « Pronos du jour » : 5 matchs, 1 / N / 2, classements et badges.
class ContestScreen extends StatefulWidget {
  const ContestScreen({super.key});

  @override
  State<ContestScreen> createState() => _ContestScreenState();
}

class _ContestScreenState extends State<ContestScreen> {
  Map<int, String> _picks = {};
  String? _loadedFor;
  bool _month = false;

  Future<void> _loadPicks(String date, String uid) async {
    final key = '$date|$uid';
    if (_loadedFor == key) return;
    _loadedFor = key;
    try {
      final picks = await AppScope.contestOf(context).myPicks(date, uid);
      if (mounted) setState(() => _picks = picks);
    } catch (_) {
      // Hors connexion : les choix réapparaîtront au prochain affichage.
    }
  }

  void _choose(String date, ContestMatch match, String choice) {
    final state = AppScope.read(context);
    final uid = state.account?.uid;
    if (uid == null || state.pseudo == null) return;
    final previous = _picks[match.fixtureId];
    setState(() => _picks = {..._picks, match.fixtureId: choice});
    // Pas d'attente : sans réseau, Firestore envoie le choix dès le retour de la connexion.
    unawaited(
      AppScope.contestOf(context).pick(date, uid, match.fixtureId, choice, state.pseudo!).catchError((Object _) {
        if (!mounted) return;
        setState(() {
          final restored = {..._picks}..remove(match.fixtureId);
          if (previous != null) restored[match.fixtureId] = previous;
          _picks = restored;
        });
        showToast(context, 'Ce match a commencé : les pronos sont fermés.');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final contest = AppScope.contestOf(context);
    final now = AppScope.repo(context).now();
    final today = dayOf(now);
    final date = dateKey(today);
    final uid = state.account?.uid;
    if (uid != null) _loadPicks(date, uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Concours du jour')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          const MutedText(
            'Prédis 1, N ou 2 sur les 5 matchs du jour. Bonne réponse : cote × 10 points. '
            'Classements de la semaine et du mois, sans argent en jeu.',
            size: 13,
          ),
          const SizedBox(height: 16),
          if (uid == null)
            _JoinPanel(
              text: 'Connecte-toi pour jouer et apparaître dans le classement.',
              action: 'Se connecter',
              onPressed: () => showLoginSheet(context),
            )
          else if (state.pseudo == null)
            const _PseudoPanel(),
          if (uid != null && state.pseudo != null) _MyStanding(uid: uid),
          const SizedBox(height: 16),
          StreamBuilder<ContestDay?>(
            stream: contest.day(date),
            builder: (context, snap) {
              final day = snap.data;
              if (day == null || day.matches.isEmpty) {
                return Panel(
                  padding: const EdgeInsets.all(16),
                  child: MutedText(
                    snap.connectionState == ConnectionState.waiting
                        ? 'Chargement du concours…'
                        : 'Le concours du jour est publié avec les pronos, chaque nuit à 00:00 GMT.',
                    size: 13,
                  ),
                );
              }
              final canPlay = uid != null && state.pseudo != null;
              return Column(
                children: [
                  for (final (i, m) in day.matches.indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _MatchCard(
                      match: m,
                      now: now,
                      picked: _picks[m.fixtureId],
                      onChoose: canPlay ? (c) => _choose(date, m, c) : null,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 26),
          SectionHeader('Classement', trailing: MutedText(_month ? 'Ce mois-ci' : 'Cette semaine')),
          const SizedBox(height: 12),
          Segmented<bool>(
            options: const [(false, 'Semaine', null), (true, 'Mois', null)],
            value: _month,
            onChanged: (v) => setState(() => _month = v),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<LeaderRow>>(
            key: ValueKey(_month),
            stream: contest.leaderboard(_month ? 'month-${monthId(today)}' : 'week-${weekId(today)}'),
            builder: (context, snap) {
              final rows = snap.data ?? const <LeaderRow>[];
              if (rows.isEmpty) {
                return const Panel(
                  padding: EdgeInsets.all(16),
                  child: MutedText('Le classement apparaît après les premiers résultats.', size: 13),
                );
              }
              return Panel(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [for (final r in rows) _LeaderTile(row: r, me: r.uid == uid)],
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const ResponsibleNote(),
        ],
      ),
    );
  }
}

class _JoinPanel extends StatelessWidget {
  const _JoinPanel({required this.text, required this.action, required this.onPressed});

  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MutedText(text, size: 13.5),
          const SizedBox(height: 12),
          WideButton(action, onPressed: onPressed),
        ],
      ),
    );
  }
}

/// Choix du pseudo affiché dans les classements.
class _PseudoPanel extends StatefulWidget {
  const _PseudoPanel();

  @override
  State<_PseudoPanel> createState() => _PseudoPanelState();
}

class _PseudoPanelState extends State<_PseudoPanel> {
  final _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final value = _field.text.trim();
    if (!validPseudo(value)) {
      setState(() => _error = '3 à 20 caractères : lettres, chiffres, espaces, . _ -');
      return;
    }
    AppScope.read(context).setPseudo(value);
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Choisis ton pseudo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const MutedText('Il apparaîtra dans les classements, à la place de ton nom.', size: 13),
          const SizedBox(height: 12),
          TextField(
            controller: _field,
            maxLength: 20,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(hintText: 'Ex. : Lion de Libreville', errorText: _error),
          ),
          const SizedBox(height: 4),
          WideButton('Valider', onPressed: _save),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.now, required this.picked, required this.onChoose});

  final ContestMatch match;
  final DateTime now;
  final String? picked;
  final ValueChanged<String>? onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = match.isOpen(now);
    final score = match.score;
    final result = match.result;
    final won = result != null && picked == result;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: MutedText('${match.league} · ${match.country}', size: 12)),
              if (result == 'void')
                const MutedText('Annulé', size: 12)
              else if (result != null && picked != null)
                Text(
                  won ? '+${match.pointsFor(result)} pts' : '0 pt',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: won ? c.winText : c.lossText),
                )
              else
                MutedText(
                  open
                      ? clock(match.kickoff.hour * 60 + match.kickoff.minute)
                      : (result != null ? 'Terminé' : 'En cours'),
                  size: 12,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${match.home} – ${match.away}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (score != null) Text('${score.home}-${score.away}', style: numStyle(20, color: c.fg)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, choice) in contestChoices.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ChoiceButton(
                    label: choiceLabel(choice),
                    odds: match.odds[choice] ?? 0,
                    points: match.pointsFor(choice),
                    selected: picked == choice,
                    correct: result == choice,
                    onTap: open && onChoose != null ? () => onChoose!(choice) : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.odds,
    required this.points,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final double odds;
  final int points;
  final bool selected;
  final bool correct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = correct ? c.win : (selected ? c.gold : c.line);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, cote ${odds.toStringAsFixed(2)}, $points points',
      child: Material(
        color: selected ? c.goldSoft : c.surface2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: selected || correct ? 1.5 : 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(odds.toStringAsFixed(2).replaceAll('.', ','), style: numStyle(16, color: c.fg)),
                MutedText('+$points pts', size: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rang de la semaine et du mois, et badges gagnés.
class _MyStanding extends StatelessWidget {
  const _MyStanding({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    return StreamBuilder<PlayerProfile?>(
      stream: AppScope.contestOf(context).player(uid),
      builder: (context, snap) {
        final p = snap.data;
        String line(Standing? s) =>
            s == null || s.rank == 0 ? '—' : '${s.rank}${s.rank == 1 ? 'er' : 'e'} · ${s.points} pts';
        final badges = [
          if (p != null && p.championships > 0) (Icons.emoji_events, 'Champion', p.championships),
          if (p != null && p.podiums > 0) (Icons.military_tech, 'Podium', p.podiums),
          if (p != null && p.perfectDays > 0) (Icons.gps_fixed, 'Sans faute', p.perfectDays),
          if (p != null && p.regularWeeks > 0) (Icons.event_available, 'Régulier', p.regularWeeks),
        ];
        return Panel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(state.pseudo ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Figure(label: 'Semaine', value: line(p?.week)),
                  ),
                  Expanded(
                    child: _Figure(label: 'Mois', value: line(p?.month)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (badges.isEmpty)
                const MutedText('Badges à gagner : champion, podium, sans faute, régulier.', size: 12)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (icon, label, count) in badges)
                      Chip(
                        avatar: Icon(icon, size: 16, color: c.goldText),
                        label: Text(count > 1 ? '$label ×$count' : label),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MutedText(label, size: 12),
      Text(value, style: numStyle(20, color: context.colors.fg)),
    ],
  );
}

class _LeaderTile extends StatelessWidget {
  const _LeaderTile({required this.row, required this.me});

  final LeaderRow row;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: me ? c.winSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text('${row.rank}', style: numStyle(17, color: row.rank <= 3 ? c.goldText : c.muted)),
          ),
          Expanded(
            child: Text(
              me ? '${row.pseudo} (toi)' : row.pseudo,
              style: TextStyle(fontSize: 14, fontWeight: me ? FontWeight.w800 : FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          MutedText('${row.correct}/${row.played}', size: 12),
          const SizedBox(width: 14),
          Text('${row.points}', style: numStyle(17, color: c.fg)),
        ],
      ),
    );
  }
}
