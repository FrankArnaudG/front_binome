import '../../../models/battleship_session.dart';

/// Résultat d'un fire() — voir BattleshipEngine.fire.
class BattleshipFireOutcome {
  final bool hit;
  final List<int>? sunkShip;
  final bool finished;
  final List<BattleshipShip> defenderFleet;

  const BattleshipFireOutcome({required this.hit, this.sunkShip, required this.finished, required this.defenderFleet});
}

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/BattleshipEngine.php`) — utilisée par les modes
/// présentiel (Nearby Connections et pass-and-play), qui ne passent
/// jamais par le serveur pendant la partie.
///
/// PREMIER moteur Dart de ce projet à manipuler un état PARTIELLEMENT
/// CACHÉ : contrairement aux autres jeux présentiel,
/// [LocalBattleshipTransport] doit activement EMPÊCHER l'affichage de la
/// flotte adverse tant qu'elle n'est pas coulée — voir l'écran "passe le
/// téléphone" dédié (BattleshipPassDeviceScreen), pas seulement une
/// question de logique de jeu mais aussi d'UI (les deux joueurs se
/// partagent le même appareil).
class BattleshipEngine {
  static const grid = 10;
  static const cellCount = grid * grid;
  static const shipSizes = [5, 4, 3, 3, 2];

  /// Lève une [ArgumentError] explicite pour chaque règle violée — voir
  /// le pendant PHP pour le détail des vérifications.
  static void validateFleet(List<BattleshipShip> ships) {
    if (ships.length != shipSizes.length) {
      throw ArgumentError('Il faut exactement ${shipSizes.length} bateaux.');
    }

    final sizes = ships.map((s) => s.cells.length).toList()..sort();
    final expected = List<int>.of(shipSizes)..sort();
    if (!_listEquals(sizes, expected)) {
      throw ArgumentError('Les tailles des bateaux ne correspondent pas.');
    }

    final occupied = <int>{};
    for (final ship in ships) {
      for (final cell in ship.cells) {
        if (cell < 0 || cell >= cellCount) throw ArgumentError('Case hors grille.');
        if (occupied.contains(cell)) throw ArgumentError('Deux bateaux ne peuvent pas se chevaucher.');
        occupied.add(cell);
      }
      _assertStraightLine(ship.cells);
    }
  }

  static void _assertStraightLine(List<int> cells) {
    final rows = cells.map((c) => c ~/ grid).toSet();
    final cols = cells.map((c) => c % grid).toSet();
    final sameRow = rows.length == 1;
    final sameCol = cols.length == 1;
    if (!sameRow && !sameCol) {
      throw ArgumentError('Un bateau doit être aligné horizontalement ou verticalement.');
    }

    final line = (sameRow ? cells.map((c) => c % grid) : cells.map((c) => c ~/ grid)).toList()..sort();
    for (var i = 1; i < line.length; i++) {
      if (line[i] != line[i - 1] + 1) {
        throw ArgumentError('Un bateau doit occuper des cases contiguës, sans trou.');
      }
    }
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Tire sur [cell] de la grille de [defenderFleet]. Lève une
  /// [ArgumentError] si [cell] est hors grille — la duplication d'un tir
  /// déjà joué est vérifiée par l'appelant (voir [myShots] côté
  /// transport), pas ici.
  static BattleshipFireOutcome fire({
    required List<BattleshipShip> defenderFleet,
    required int cell,
  }) {
    if (cell < 0 || cell >= cellCount) {
      throw ArgumentError('Case invalide.');
    }

    var hit = false;
    List<int>? sunkShip;
    final newFleet = <BattleshipShip>[];
    for (final ship in defenderFleet) {
      if (!hit && ship.cells.contains(cell)) {
        hit = true;
        final updated = ship.withHit(cell);
        if (updated.isSunk) sunkShip = updated.cells;
        newFleet.add(updated);
      } else {
        newFleet.add(ship);
      }
    }

    final finished = newFleet.every((s) => s.isSunk);

    return BattleshipFireOutcome(hit: hit, sunkShip: sunkShip, finished: finished, defenderFleet: newFleet);
  }

  /// Bateaux ENTIÈREMENT COULÉS de [opponentFleet] — la SEULE information
  /// sur la flotte adverse qu'il est jamais sûr de transmettre (voir
  /// BattleshipEngine::toPublicArrayFor côté PHP, même logique) —
  /// réutilisé par les modes présentiel (Nearby et pass-and-play) pour ne
  /// jamais construire un [BattleshipBoardState] qui fuiterait un bateau
  /// adverse encore vivant.
  static List<List<int>> sunkShipsOf(List<BattleshipShip> opponentFleet) =>
      [for (final ship in opponentFleet) if (ship.isSunk) ship.cells];
}
