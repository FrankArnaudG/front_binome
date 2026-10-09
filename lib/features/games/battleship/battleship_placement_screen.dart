import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/battleship_session.dart';
import '../../../models/game.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../nearby/nearby_comms.dart';
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
  // Simple relais vers BattleshipBoardScreen.onRematch (voir demande
  // utilisateur) — cet écran de placement n'en a lui-même pas besoin,
  // mais doit le conserver le temps de construire le plateau de combat
  // qui, lui, affiche le bouton "Rejouer".
  final Future<void> Function(BuildContext context)? onRematch;
  // Simples relais vers BattleshipBoardScreen (voir ses commentaires).
  final bool isLauncher;
  final Future<void> Function(BuildContext context)? onQuit;
  // Simple relais vers BattleshipBoardScreen (voir NearbyComms) — cet écran
  // de placement n'affiche pas de chat lui-même, il transmet juste le
  // canal jusqu'au plateau de combat.
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const BattleshipPlacementScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.onRematch,
    this.isLauncher = true,
    this.onQuit,
    this.nearbyComms,
    this.nearbyMyName,
    this.nearbyPartnerName,
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

  // Voir demande utilisateur : "au lieu d'indiquer une seule case, indique
  // les 4, là on sait vraiment où ça sera positionné" — l'ensemble des
  // cases que le bateau occuperait s'il était déposé ICI (recalculé à
  // chaque case survolée), et si cette position est valide (déposable en
  // vert/bleu) ou non (hors grille/déjà occupée, en rouge).
  Set<int>? _hoverPreviewCells;
  bool _hoverPreviewValid = false;

  // Sourcé depuis l'état vivant du transport — c'est lui qui porte la
  // taille de grille choisie avant placement (voir BattleshipBoardState.gridSize).
  int get _gridSize => _state.gridSize;
  List<int> get _shipSizes => BattleshipEngine.shipSizesFor(_gridSize);

  List<int> get _remainingSizes {
    final placed = _placedShips.map((s) => s.cells.length).toList();
    final remaining = List<int>.of(_shipSizes);
    for (final size in placed) {
      remaining.remove(size);
    }
    return remaining;
  }

  // Voir demande utilisateur (capture : un téléphone restait bloqué sur
  // "En attente..." alors que l'autre était déjà passé au combat) —
  // évite un double push si _submit() a déjà basculé vers le plateau au
  // moment même de la soumission (voir plus bas).
  bool _navigatedToBoard = false;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
  }

  /// Contrairement à _submit() (qui ne vérifie l'état du binôme qu'À
  /// L'INSTANT où JE viens de soumettre ma flotte), cet écran doit aussi
  /// réagir si c'est le BINÔME qui devient prêt EN DERNIER, pendant que je
  /// suis déjà sur l'écran d'attente — sans ça, rien ne fait jamais
  /// avancer cet écran une fois qu'on y est entré (voir demande
  /// utilisateur).
  void _onState(BattleshipBoardState s) {
    if (!mounted) return;
    setState(() => _state = s);
    if (!_isLocal && !_navigatedToBoard && s.myReady && s.opponentReady) {
      _navigatedToBoard = true;
      _pushBoard(replace: true);
    }
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
    final row = startCell ~/ _gridSize;
    final col = startCell % _gridSize;
    final cells = <int>[];
    for (var i = 0; i < size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      if (r >= _gridSize || c >= _gridSize) return null;
      cells.add(r * _gridSize + c);
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

  /// Un bateau posé garde son orientation propre (pas le bouton pivoter
  /// global, qui ne concerne que les prochains bateaux tirés du bac) tant
  /// qu'on le déplace sans le retirer — voir demande utilisateur : "on
  /// doit pouvoir les déplacer et repositionner tant qu'on n'a pas validé".
  bool _isHorizontalShip(BattleshipShip ship) {
    if (ship.cells.length < 2) return true;
    final row0 = ship.cells.first ~/ _gridSize;
    return ship.cells.every((c) => c ~/ _gridSize == row0);
  }

  /// Reconstitue le point de départ du bateau à partir de la case DÉPOSÉE
  /// et du segment SAISI (voir demande utilisateur : "c'est le bout du
  /// navire qui se déplace" — sans ça, déposer n'importe quel segment
  /// faisait toujours de cette case le nouveau début, recalant tout le
  /// bateau dans une direction inattendue). [grabIndex] est la position
  /// (0 = première case) du segment saisi le long du bateau — la case
  /// déposée doit rester exactement sous ce même segment.
  int? _startCellForDrop(int droppedCell, bool horizontal, int grabIndex) {
    final row = droppedCell ~/ _gridSize;
    final col = droppedCell % _gridSize;
    final startRow = horizontal ? row : row - grabIndex;
    final startCol = horizontal ? col - grabIndex : col;
    if (startRow < 0 || startCol < 0) return null;
    return startRow * _gridSize + startCol;
  }

  /// Exclut [ship] lui-même de l'ensemble occupé, sinon il se bloquerait
  /// sur ses propres anciennes cases.
  bool _canMoveTo(int droppedCell, BattleshipShip ship, int grabIndex) {
    final horizontal = _isHorizontalShip(ship);
    final startCell = _startCellForDrop(droppedCell, horizontal, grabIndex);
    if (startCell == null) return false;
    final cells = _shipCellsAt(startCell, ship.cells.length, horizontal);
    if (cells == null) return false;
    final occupied = {for (final s in _placedShips) if (s != ship) ...s.cells};
    return !cells.any(occupied.contains);
  }

  void _moveShip(BattleshipShip ship, int droppedCell, int grabIndex) {
    if (!_canMoveTo(droppedCell, ship, grabIndex)) return;
    final horizontal = _isHorizontalShip(ship);
    final startCell = _startCellForDrop(droppedCell, horizontal, grabIndex);
    if (startCell == null) return;
    final cells = _shipCellsAt(startCell, ship.cells.length, horizontal);
    if (cells == null) return;
    setState(() {
      _placedShips.remove(ship);
      _placedShips.add(BattleshipShip(cells: cells));
    });
  }

  /// Appelée à chaque case survolée pendant un glisser (nouveau bateau du
  /// bac OU bateau déjà posé qu'on déplace) — voir demande utilisateur :
  /// prévisualiser TOUTES les cases concernées, pas seulement celle sous
  /// le doigt.
  void _updateHoverPreview(int cell, Object? data) {
    List<int>? cells;
    bool valid = false;
    if (data is int) {
      cells = _shipCellsAt(cell, data, _horizontal);
      if (cells != null) {
        final occupied = {for (final s in _placedShips) ...s.cells};
        valid = !cells.any(occupied.contains);
      }
    } else if (data is _ShipDrag) {
      final horizontal = _isHorizontalShip(data.ship);
      final startCell = _startCellForDrop(cell, horizontal, data.grabIndex);
      if (startCell != null) {
        cells = _shipCellsAt(startCell, data.ship.cells.length, horizontal);
        if (cells != null) {
          final occupied = {for (final s in _placedShips) if (s != data.ship) ...s.cells};
          valid = !cells.any(occupied.contains);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _hoverPreviewCells = cells?.toSet();
      _hoverPreviewValid = valid;
    });
  }

  void _clearHoverPreview() {
    if (!mounted || _hoverPreviewCells == null) return;
    setState(() => _hoverPreviewCells = null);
  }

  Future<void> _submit() async {
    if (_placedShips.length != _shipSizes.length || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.transport.submitFleet(_placedShips);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : LocaleScope.t(context, 'battleship_placement_error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
              onRematch: widget.onRematch,
              isLauncher: widget.isLauncher,
              onQuit: widget.onQuit,
            ),
          ),
        );
      }
    } else if (state.opponentReady && !_navigatedToBoard) {
      _navigatedToBoard = true;
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
        onRematch: widget.onRematch,
        isLauncher: widget.isLauncher,
        onQuit: widget.onQuit,
        nearbyComms: widget.nearbyComms,
        nearbyMyName: widget.nearbyMyName,
        nearbyPartnerName: widget.nearbyPartnerName,
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
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridSize),
                          itemCount: _gridSize * _gridSize,
                          itemBuilder: (context, cell) {
                            final isOccupied = occupied.contains(cell);
                            final shipAtCell = isOccupied
                                ? _placedShips.firstWhere((s) => s.cells.contains(cell))
                                : null;
                            return DragTarget<Object>(
                              onWillAcceptWithDetails: (details) {
                                final data = details.data;
                                _updateHoverPreview(cell, data);
                                if (data is int) return _canPlaceAt(cell, data);
                                if (data is _ShipDrag) return _canMoveTo(cell, data.ship, data.grabIndex);
                                return false;
                              },
                              onAcceptWithDetails: (details) {
                                final data = details.data;
                                if (data is int) _placeShip(cell, data);
                                if (data is _ShipDrag) _moveShip(data.ship, cell, data.grabIndex);
                              },
                              builder: (context, candidate, rejected) {
                                // Voir demande utilisateur : "indique les 4,
                                // là on sait vraiment où ça sera positionné"
                                // — toutes les cases que le bateau
                                // occuperait à CETTE position de survol,
                                // pas seulement celle sous le doigt ; rouge
                                // si ça déborderait de la grille ou
                                // chevaucherait un bateau déjà posé.
                                final previewing = _hoverPreviewCells?.contains(cell) ?? false;
                                final previewColor = _hoverPreviewValid ? _kShipColor : Colors.redAccent;
                                final cellVisual = Container(
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    color: isOccupied
                                        ? _kShipColor
                                        : previewing
                                            ? previewColor.withValues(alpha: 0.4)
                                            : theme.surface.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                                if (shipAtCell == null) return cellVisual;

                                // Voir demande utilisateur : "pas besoin
                                // d'appuyer longtemps, il suffit de poser le
                                // doigt et de le déplacer" — Draggable (pas
                                // LongPressDraggable), même geste immédiat
                                // que pour un bateau tiré du bac. Le tap
                                // court (sans déplacement) continue de
                                // retirer, les deux gestes coexistent sans
                                // conflit tant qu'il n'y a pas de mouvement.
                                return Draggable<_ShipDrag>(
                                  data: _ShipDrag(ship: shipAtCell, grabIndex: shipAtCell.cells.indexOf(cell)),
                                  onDragEnd: (_) => _clearHoverPreview(),
                                  feedback: _ShipStrip(
                                    size: shipAtCell.cells.length,
                                    horizontal: _isHorizontalShip(shipAtCell),
                                    color: _kShipColor,
                                    cellSize: 22,
                                  ),
                                  childWhenDragging: Container(
                                    margin: const EdgeInsets.all(1),
                                    decoration: BoxDecoration(
                                      color: _kShipColor.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  child: GestureDetector(
                                    onTap: () => _removeShipAt(cell),
                                    child: cellVisual,
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
                    Row(
                      children: [
                        Text(
                          LocaleScope.t(context, 'battleship_ships_to_place'),
                          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                        ),
                        const Spacer(),
                        // Voir demande utilisateur : déplacé depuis l'AppBar
                        // (en haut à droite) jusqu'ici, juste au-dessus du
                        // bac de navires à placer, toujours aligné à droite.
                        IconButton(
                          icon: const Icon(Icons.rotate_90_degrees_ccw_rounded),
                          tooltip: LocaleScope.t(context, 'battleship_rotate_tooltip'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _horizontal = !_horizontal),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Voir demande utilisateur (capture : les bateaux
                    // débordaient de l'écran, bande jaune/noire de Flutter
                    // visible) — la flotte complète (5+4+3+3+2 cases) ne
                    // tient pas toujours en largeur, notamment sur un écran
                    // étroit ou en orientation portrait haute densité.
                    //
                    // Voir demande utilisateur (2e capture, après appui sur
                    // le bouton pivoter en haut à droite) : une fois les
                    // bateaux affichés à la verticale (_horizontal = false),
                    // le plus long (5 cases × 20px) dépasse largement une
                    // hauteur fixe de 56px — débordement vertical, même bande
                    // jaune/noire de Flutter, cette fois en hauteur.
                    SizedBox(
                      height: _horizontal ? 56 : _shipSizes.reduce((a, b) => a > b ? a : b) * 20.0 + 8,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final size in _remainingSizes) ...[
                              Draggable<int>(
                                data: size,
                                onDragEnd: (_) => _clearHoverPreview(),
                                feedback: _ShipStrip(size: size, horizontal: _horizontal, color: _kShipColor, cellSize: 22),
                                childWhenDragging: _ShipStrip(size: size, horizontal: _horizontal, color: Colors.grey, cellSize: 18, faded: true),
                                child: _ShipStrip(size: size, horizontal: _horizontal, color: _kShipColor, cellSize: 18),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _placedShips.length == _shipSizes.length && !_submitting ? _submit : null,
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

/// Charge utile d'un glisser-déplacer sur un bateau DÉJÀ posé — [grabIndex]
/// (0 = première case du bateau) retient quel segment a été saisi, pour
/// que ce même segment reste sous le point déposé (voir
/// _BattleshipPlacementScreenState._startCellForDrop).
class _ShipDrag {
  final BattleshipShip ship;
  final int grabIndex;

  const _ShipDrag({required this.ship, required this.grabIndex});
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
