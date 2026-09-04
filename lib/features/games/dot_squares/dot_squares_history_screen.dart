import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/dot_square_session.dart';
import '../../../models/game.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_service.dart';

/// Historique des feuilles terminées de "Le Jeu des Carrés" pour cette Box
/// — voir demande utilisateur : "ajouter un historique pour conserver
/// chaque feuille avec ces statistiques". Nouveauté propre à ce jeu, aucun
/// autre jeu de l'app n'a d'écran équivalent (voir
/// DotSquaresController::index).
class DotSquaresHistoryScreenLoader extends StatefulWidget {
  final Game game;
  final AppUser user;

  const DotSquaresHistoryScreenLoader({super.key, required this.game, required this.user});

  @override
  State<DotSquaresHistoryScreenLoader> createState() => _DotSquaresHistoryScreenLoaderState();
}

class _DotSquaresHistoryScreenLoaderState extends State<DotSquaresHistoryScreenLoader> {
  final _items = <DotSquareSession>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    setState(() { _loading = true; _error = null; });
    try {
      final page = await GameService.instance.fetchDotSquaresHistory(widget.game.id);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = LocaleScope.t(context, 'dot_squares_history_error'); });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await GameService.instance.fetchDotSquaresHistory(widget.game.id, beforeId: _items.last.id);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(widget.user.id);
    final playerNames = <String, String>{
      widget.user.id: widget.user.prenom,
      if (partner != null) partner.id: partner.prenom,
    };

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          LocaleScope.t(context, 'dot_squares_history_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              LocaleScope.t(context, 'dot_squares_history_empty'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index == _items.length) {
                              return Center(
                                child: _loadingMore
                                    ? CircularProgressIndicator(color: theme.primary)
                                    : TextButton(
                                        onPressed: _loadMore,
                                        child: Text(LocaleScope.t(context, 'dot_squares_history_load_more')),
                                      ),
                              );
                            }
                            return _DotSquareHistoryTile(session: _items[index], playerNames: playerNames);
                          },
                        ),
        ),
      ),
    );
  }
}

class _DotSquareHistoryTile extends StatelessWidget {
  final DotSquareSession session;
  final Map<String, String> playerNames;

  const _DotSquareHistoryTile({required this.session, required this.playerNames});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final duration = session.startedAt != null && session.finishedAt != null
        ? session.finishedAt!.difference(session.startedAt!)
        : null;
    final durationLabel = duration != null ? '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}' : '—';
    final finishedAt = session.finishedAt;
    final dateLabel = finishedAt != null
        ? '${finishedAt.day.toString().padLeft(2, '0')}/${finishedAt.month.toString().padLeft(2, '0')}/${finishedAt.year}'
        : '';

    final ids = playerNames.keys.toList()..sort();
    final scoreLine = ids.map((id) => '${playerNames[id] ?? '?'} : ${session.scoresByUser[id] ?? 0}').join(' · ');

    final resultLabel = session.isTie
        ? LocaleScope.t(context, 'dot_squares_score_tie')
        : LocaleScope.t(context, 'dot_squares_score_winner', {
            'name': playerNames[session.winnerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
          });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  resultLabel,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(dateLabel, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(scoreLine, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 14, color: theme.textOnBackgroundMuted),
              const SizedBox(width: 4),
              Text(durationLabel, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
              const SizedBox(width: 12),
              Icon(Icons.category_outlined, size: 14, color: theme.textOnBackgroundMuted),
              const SizedBox(width: 4),
              Text(
                '${session.rectangles.length}',
                style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
              ),
              if (session.closedEarly) ...[
                const SizedBox(width: 12),
                Icon(Icons.handshake_outlined, size: 14, color: theme.textOnBackgroundMuted),
                const SizedBox(width: 4),
                Text(
                  LocaleScope.t(context, 'dot_squares_history_closed_early'),
                  style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
