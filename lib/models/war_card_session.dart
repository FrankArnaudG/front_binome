/// L'état d'une partie de "Bataille", mode à distance (voir
/// WarCardController) — reçu au démarrage puis à chaque événement temps
/// réel `WarCardUpdated`, le client remplace son état local par celui-ci
/// plutôt que de tenter un patch partiel (même principe que les autres
/// jeux).
///
/// TROISIÈME pattern de synchronisation de ce projet (voir
/// NumberHuntSession pour le second) : ni tour par tour, ni "n'importe
/// qui n'importe quand", mais "les deux doivent taper avant que la
/// manche résolve" (voir [pendingFlipCreator]/[pendingFlipPartner]).
class WarCardSession {
  final String id;
  // Numéro de version serveur (voir HasStateVersion) : 0 = serveur sans versionnement.
  final int version;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — [playerOneId]/[playerTwoId] portent alors
  // les deux joueurs à la place de box->creator_id/partner_id (même
  // principe que TicTacToeSession).
  final String? boxId;
  final String? playerOneId;
  final String? playerTwoId;
  final String gameId;
  final String? createdBy;
  final int deckSize;
  final List<String> deck;
  final bool dealt;
  final bool readyCreator;
  final bool readyPartner;
  final bool started;
  final List<String>? pileCreator;
  final List<String>? pilePartner;
  final bool pendingFlipCreator;
  final bool pendingFlipPartner;
  final List<String> battlePot;
  final List<Map<String, String>> lastRoundResult;
  final int roundsCount;
  final String? winnerUserId;
  final bool isTie;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const WarCardSession({
    required this.id,
    this.version = 0,
    this.boxId,
    this.playerOneId,
    this.playerTwoId,
    required this.gameId,
    this.createdBy,
    this.deckSize = 52,
    this.deck = const [],
    this.dealt = true,
    this.readyCreator = false,
    this.readyPartner = false,
    this.started = true,
    this.pileCreator,
    this.pilePartner,
    this.pendingFlipCreator = false,
    this.pendingFlipPartner = false,
    this.battlePot = const [],
    this.lastRoundResult = const [],
    this.roundsCount = 0,
    this.winnerUserId,
    this.isTie = false,
    this.abandoned = false,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.pausedByUserId,
  });

  bool get isFinished => finishedAt != null;
  bool get isPaused => pausedAt != null;
  bool get isFriendSession => boxId == null;

  factory WarCardSession.fromJson(Map<String, dynamic> json) => WarCardSession(
        id: json['id'] as String,
        version: (json['version'] as num?)?.toInt() ?? 0,
        boxId: json['box_id'] as String?,
        playerOneId: json['player_one_id'] as String?,
        playerTwoId: json['player_two_id'] as String?,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        deckSize: json['deck_size'] as int? ?? 52,
        deck: (json['deck'] as List?)?.map((e) => e as String).toList() ?? const [],
        dealt: json['dealt'] as bool? ?? true,
        readyCreator: json['ready_creator'] as bool? ?? false,
        readyPartner: json['ready_partner'] as bool? ?? false,
        started: json['started'] as bool? ?? true,
        pileCreator: (json['pile_creator'] as List?)?.map((e) => e as String).toList(),
        pilePartner: (json['pile_partner'] as List?)?.map((e) => e as String).toList(),
        pendingFlipCreator: json['pending_flip_creator'] as bool? ?? false,
        pendingFlipPartner: json['pending_flip_partner'] as bool? ?? false,
        battlePot: (json['battle_pot'] as List?)?.map((e) => e as String).toList() ?? const [],
        lastRoundResult: _parseRounds(json['last_round_result']),
        roundsCount: json['rounds_count'] as int? ?? 0,
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
}

/// `last_round_result` est `{rounds: [{creator: "7S", partner: "7H"}, ...]}`
/// — PHP encode `null` (aucune manche jouée encore) comme JSON `null`, pas
/// comme un objet vide, d'où ce parsing dédié.
List<Map<String, String>> _parseRounds(dynamic value) {
  if (value is! Map) return const [];
  final rounds = value['rounds'];
  if (rounds is! List) return const [];
  return rounds
      .whereType<Map>()
      .map((r) => r.map((k, v) => MapEntry(k as String, v as String)))
      .toList();
}

/// Réponse d'un appel `flip` côté à distance — [resolved] indique si LES
/// DEUX joueurs avaient déjà tapé (donc si la manche vient d'être
/// résolue) ou si on attend encore l'autre.
class WarCardFlipResult {
  final WarCardSession session;
  final bool resolved;

  const WarCardFlipResult({required this.session, required this.resolved});

  factory WarCardFlipResult.fromJson(Map<String, dynamic> json) => WarCardFlipResult(
        session: WarCardSession.fromJson(json),
        resolved: json['resolved'] as bool? ?? false,
      );
}

/// Résultat de fin de partie pour une session donnée (voir
/// WarCardController::stats).
class WarCardMatchStats {
  final String? winnerUserId;
  final bool isTie;
  final int roundsCount;
  final int? durationSeconds;

  const WarCardMatchStats({
    this.winnerUserId,
    this.isTie = false,
    this.roundsCount = 0,
    this.durationSeconds,
  });

  factory WarCardMatchStats.fromJson(Map<String, dynamic> json) => WarCardMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        roundsCount: json['rounds_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
