/// Score d'UN membre du couple pour une partie de "Jeu de Mémoire" —
/// contrairement aux autres jeux, il n'y a pas de "temps/coups par
/// joueur" : le plateau est partagé, donc le seul score individuel qui a
/// du sens est le nombre de paires trouvées (voir demande utilisateur).
/// Durée totale et nombre de coups restent des infos de PARTIE, pas de
/// joueur (voir MemoryGameMatchStats).
class MemoryGamePlayerStats {
  final String userId;
  final String? prenom;
  final String? avatar;
  final int pairsFound;

  const MemoryGamePlayerStats({
    required this.userId,
    this.prenom,
    this.avatar,
    required this.pairsFound,
  });

  factory MemoryGamePlayerStats.fromJson(Map<String, dynamic> json) => MemoryGamePlayerStats(
        userId: json['user_id'] as String,
        prenom: json['prenom'] as String?,
        avatar: json['avatar'] as String?,
        pairsFound: json['pairs_found'] as int? ?? 0,
      );
}

/// Score de fin de partie — voir MemoryGamePlayerStats pour le détail par
/// joueur·se ; [durationSeconds]/[movesCount] sont affichés en info
/// secondaire (voir memory_game_match_scoreboard.dart), jamais comme un
/// classement individuel.
class MemoryGameMatchStats {
  final List<MemoryGamePlayerStats> players;
  final int movesCount;
  final int? durationSeconds;
  final String? winnerUserId;

  const MemoryGameMatchStats({
    required this.players,
    required this.movesCount,
    this.durationSeconds,
    this.winnerUserId,
  });

  factory MemoryGameMatchStats.fromJson(Map<String, dynamic> json) => MemoryGameMatchStats(
        players: (json['players'] as List? ?? const [])
            .map((e) => MemoryGamePlayerStats.fromJson(e as Map<String, dynamic>))
            .toList(),
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
        winnerUserId: json['winner_user_id'] as String?,
      );
}
