/// Score d'UN membre du couple, pris comme devineur·se, pour "Devine mon
/// émoji" dans la Box courante (voir EmojiStoryController::stats) —
/// [proposed] compte CHAQUE tentative envoyée (même sur une story qui
/// finira par en compter plusieurs), tandis que [firstTry]/[afterFirstTry]/
/// [missed] classent les STORIES résolues (voir EmojiStorySend.isResolved)
/// selon leur issue : trouvée dès la première proposition, trouvée après
/// une ou plusieurs chances supplémentaires, ou jamais trouvée.
class EmojiStoryPlayerStats {
  final String userId;
  final String? prenom;
  final String? avatar;
  final int proposed;
  final int firstTry;
  final int afterFirstTry;
  final int missed;
  final int resolvedTotal;
  final double firstTryPercentage;

  const EmojiStoryPlayerStats({
    required this.userId,
    this.prenom,
    this.avatar,
    required this.proposed,
    required this.firstTry,
    required this.afterFirstTry,
    required this.missed,
    required this.resolvedTotal,
    required this.firstTryPercentage,
  });

  factory EmojiStoryPlayerStats.fromJson(Map<String, dynamic> json) => EmojiStoryPlayerStats(
        userId: json['user_id'] as String,
        prenom: json['prenom'] as String?,
        avatar: json['avatar'] as String?,
        proposed: json['proposed'] as int? ?? 0,
        firstTry: json['first_try'] as int? ?? 0,
        afterFirstTry: json['after_first_try'] as int? ?? 0,
        missed: json['missed'] as int? ?? 0,
        resolvedTotal: json['resolved_total'] as int? ?? 0,
        firstTryPercentage: (json['first_try_percentage'] as num?)?.toDouble() ?? 0,
      );
}

/// Score "façon match" des deux membres du couple pour ce jeu — voir
/// EmojiStoryPlayerStats pour le détail par joueur·se. Le classement (voir
/// EmojiStorySessionScreen._MatchScoreboard) se fait sur
/// [EmojiStoryPlayerStats.firstTryPercentage], pas sur les comptes bruts :
/// un binôme confronté à beaucoup plus de stories que l'autre resterait
/// sinon injustement avantagé/désavantagé.
class EmojiStoryMatchStats {
  final List<EmojiStoryPlayerStats> players;

  const EmojiStoryMatchStats({required this.players});

  factory EmojiStoryMatchStats.fromJson(Map<String, dynamic> json) => EmojiStoryMatchStats(
        players: (json['players'] as List? ?? const [])
            .map((e) => EmojiStoryPlayerStats.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Total "trouvé du premier coup" tous membres confondus — utile pour le
  /// petit badge compact (voir l'AppBar de EmojiStorySessionScreen), qui
  /// n'a besoin que d'un résumé, pas du détail par joueur·se.
  int get totalFirstTry => players.fold(0, (sum, p) => sum + p.firstTry);

  int get totalResolved => players.fold(0, (sum, p) => sum + p.resolvedTotal);
}
