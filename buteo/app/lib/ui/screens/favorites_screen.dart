import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/tip_card.dart';

/// Choix des équipes suivies. Leurs matchs du jour s'affichent sur l'accueil.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final q = _fold(_query.trim());
    final groups = [
      for (final g in AppScope.repo(context).teamGroups())
        (
          g,
          g.teams
              .where(
                (t) => q.isEmpty || _fold(t).contains(q) || _fold(g.league).contains(q) || _fold(g.country).contains(q),
              )
              .toList(),
        ),
    ].where((e) => e.$2.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes équipes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          MutedText(
            state.favoriteCount == 0
                ? 'Touche l’étoile des équipes que tu suis : leurs matchs du jour s’afficheront sur l’accueil.'
                : '${state.favoriteCount} suivie${state.favoriteCount > 1 ? 's' : ''}. '
                      'Leurs matchs du jour s’affichent sur l’accueil.',
            size: 13,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher une équipe, un pays…',
              prefixIcon: Icon(Icons.search_rounded, color: c.muted),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: MutedText('Aucune équipe ne correspond à « $_query ».', align: TextAlign.center),
            ),
          for (final (g, teams) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
              child: Row(
                children: [
                  Icon(sportIcon(g.sport), size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Eyebrow('${g.country} · ${g.league}')),
                ],
              ),
            ),
            Panel(
              child: Column(
                children: [
                  for (final (i, team) in teams.indexed)
                    _TeamRow(team: team, sport: g.sport, divider: i < teams.length - 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, required this.sport, required this.divider});

  final String team;
  final Sport sport;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AppScope.of(context);
    final on = state.isFavorite(sport, team);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: c.line, width: .5)) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: () => state.toggleFavorite(sport, team),
          title: Text(team, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          trailing: Icon(
            on ? Icons.star_rounded : Icons.star_outline_rounded,
            color: on ? c.goldText : c.faint,
            semanticLabel: on ? 'Suivie' : 'Non suivie',
          ),
        ),
      ),
    );
  }
}

void openFavorites(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()));
