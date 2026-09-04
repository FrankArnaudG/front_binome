import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/battleship_session.dart';
import '../../../models/game.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import 'battleship_board_screen.dart';
import 'battleship_engine.dart';
import 'battleship_transport.dart';
import 'battleship_transport_local.dart';

const _kShipColor = Color(0xFF2F6FED);

/// Placement PRIVÉ de sa flotte avant le combat — glisser-déposer un
/// bateau depuis le plateau du bas sur la grille, pivoter avec le bouton
/// dédié (voir demande utilisateur : "placement manuel, glisser +
/// pivoter"). Écran RÉUTILISÉ pour chaque viewer en pass-and-play (voir
/// [LocalBattleshipTransport.setActiveViewer]) : une instance = UNE
/// personne qui place, jamais les deux flottes visibles en même temps.
class BattleshipPlacementScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final BattleshipTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;

  const BattleshipPlacementScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
  });

  @override
  State<BattleshipPlacementScreen> createState() => _BattleshipPlacementScreenState();
}

class _BattleshipPlacementScreenState extends State<BattleshipPlacementScreen> {
  late StreamSubscription<BattleshipBoardState> _subscription;
  late BattleshipBoardState _state;

  bool get _isLocal => widget.transport is LocalBattleshipTransport;

  // Le "gate" (écran "passe le téléphone") ne s'affiche qu'en local, et
  // seulement le temps que la personne confirme être prête à regarder.
  late bool _gateRevealed = !_isLocal;

  final List<BattleshipShip> _placedShips = [];
  bool _horizontal = true;
  bool _submitting = false;

  List<int> get _remainingSizes {
    final placed = _placedShips.map((s) => s.cells.length).toList();
    final remaining = List<int>.of(BattleshipEngine.shipSizes);
    for (final size in placed) {
      remaining.remove(size);
    }
    return remaining;
  }

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  String _otherUserId() => widget.playerNames.keys.firstWhere((id) => id != _state.myUserId);

  bool _canPlaceAt(int startCell, int size) {
    final cells = _shipCellsAt(startCell, size, _horizontal);
    if (cells == null) return false;
    final occupied = {for (final s in _placedShips) ...s.cells};
    return !cells.any(occupied.contains);
  }

  List<int>? _shipCellsAt(int startCell, int size, bool horizontal) {
    final row = startCell ~/ BattleshipEngine.grid;
    final col = startCell % BattleshipEngine.grid;
    final cells = <int>[];
    for (var i = 0; i < size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      if (r >= BattleshipEngine.grid || c >= BattleshipEngine.grid) return null;
      cells.add(r * BattleshipEngine.grid + c);
    }
    return cells;
  }

  void _placeShip(int startCell, int size) {
    final cells = _shipCellsAt(startCell, size, _horizontal);
    if (cells == null) return;
    if (!_canPlaceAt(startCell, size)) return;
    setState(() => _placedShips.add(BattleshipShip(cells: cells)));
  }

  void _removeShipAt(int cell) {
    setState(() => _placedShips.removeWhere((s) => s.cells.contains(cell)));
  }

  Future<void> _submit() async {
    if (_placedShips.length != BattleshipEngine.shipSizes.length || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.transport.submitFleet(_placedShips);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleScope.t(context, 'battleship_placement_error'))),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
    if (!mounted) return;

    final state = widget.transport.currentState;
    if (_isLocal) {
      final localTransport = widget.transport as LocalBattleshipTransport;
      if (state.opponentReady) {
        // Les deux flottes sont prêtes — bascule vers le combat, en
        // commençant par la personne créatrice (voir BattleshipEngine).
        localTransport.setActiveViewer(widget.user.id);
        _pushBoard(replace: true);
      } else {
        localTransport.setActiveViewer(_otherUserId());
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BattleshipPlacementScreen(
              game: widget.game,
              user: widget.user,
              transport: widget.transport,
              playerNames: widget.playerNames,
              playerAvatars: widget.playerAvatars,
            ),
          ),
        );
      }
    } else if (state.opponentReady) {
      _pushBoard(replace: true);
    }
    // Sinon (à distance/présentiel connecté, adversaire pas encore prêt) :
    // reste sur cet écran, voir build() qui bascule sur l'indicateur
    // d'attente dès que `_state.myReady` est vrai.
  }

  void _pushBoard({bool replace = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => BattleshipBoardScreen(
        game: widget.game,
        user: widget.user,
        transport: widget.transport,
        playerNames: widget.playerNames,
        playerAvatars: widget.playerAvatars,
      ),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final viewerName = widget.playerNames[_state.myUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback');

    if (_isLocal && !_gateRevealed) {
      return Scaffold(
        backgroundColor: theme.background,
        body: ThemedBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_rounded, size: 48, color: theme.primary),
                    const SizedBox(height: 16),
                    Text(
                      LocaleScope.t(context, 'battleship_pass_device_title', {'name': viewerName}),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LocaleScope.t(context, 'battleship_pass_device_subtitle'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => setState(() => _gateRevealed = true),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                      child: Text(LocaleScope.t(context, 'battleship_pass_device_ready')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_state.myReady && !_isLocal) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: theme.statusBarOverlayStyle,
          foregroundColor: theme.textOnBackground,
        ),
        body: ThemedBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: theme.primary),
                    const SizedBox(height: 16),
                    Text(
                      LocaleScope.t(context, 'battleship_waiting_opponent'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final occupied = {for (final s in _placedShips) ...s.cells};

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          LocaleScope.t(context, 'battleship_placement_title', {'name': viewerName}),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_90_degrees_ccw_rounded),
            tooltip: LocaleScope.t(context, 'battleship_rotate_tooltip'),
            onPressed: () => setState(() => _horizontal = !_horizontal),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  LocaleScope.t(context, 'battleship_placement_subtitle'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: BattleshipEngine.grid),
                          itemCount: BattleshipEngine.cellCount,
                          itemBuilder: (context, cell) {
                            final isOccupied = occupied.contains(cell);
                            return DragTarget<int>(
                              onWillAcceptWithDetails: (details) => _canPlaceAt(cell, details.data),
                              onAcceptWithDetails: (details) => _placeShip(cell, details.data),
                              builder: (context, candidate, rejected) {
                                final highlighting = candidate.isNotEmpty;
                                return GestureDetector(
                                  onTap: isOccupied ? () => _removeShipAt(cell) : null,
                                  child: Container(
                                    margin: const EdgeInsets.all(1),
                                    decoration: BoxDecoration(
                                      color: isOccupied
                                          ? _kShipColor
                                          : highlighting
                                              ? _kShipColor.withValues(alpha: 0.35)
                                              : theme.surface.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      LocaleScope.t(context, 'battleship_ships_to_place'),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final size in _remainingSizes) ...[
                            Draggable<int>(
                              data: size,
                              feedback: _ShipStrip(size: size, horizontal: _horizontal, color: _kShipColor, cellSize: 22),
                              childWhenDragging: _ShipStrip(size: size, horizontal: _horizontal, color: Colors.grey, cellSize: 18, faded: true),
                              child: _ShipStrip(size: size, horizontal: _horizontal, color: _kShipColor, cellSize: 18),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _placedShips.length == BattleshipEngine.shipSizes.length && !_submitting ? _submit : null,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(LocaleScope.t(context, 'battleship_confirm_fleet')),
                    ),
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

class _ShipStrip extends StatelessWidget {
  final int size;
  final bool horizontal;
  final Color color;
  final double cellSize;
  final bool faded;

  const _ShipStrip({required this.size, required this.horizontal, required this.color, required this.cellSize, this.faded = false});

  @override
  Widget build(BuildContext context) {
    final children = List.generate(
      size,
      (_) => Container(
        width: cellSize,
        height: cellSize,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: faded ? 0.3 : 1),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
    return horizontal ? Row(mainAxisSize: MainAxisSize.min, children: children) : Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
