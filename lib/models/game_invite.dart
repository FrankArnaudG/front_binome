/// Une invitation à une partie à distance (Jeu de Mémoire/Morpion/Le Jeu
/// des Carrés) — voir GameInviteController côté backend. [status] :
/// `pending` (en attente de réponse), `accepted` (voir [sessionId], la
/// vraie partie), `declined`, ou `expired` (60s sans réponse, voir
/// [expiresAt]).
class GameInvite {
  final String id;
  final String boxId;
  final String gameId;
  final String sessionType;
  final String inviterId;
  final String inviteeId;
  final String status;
  final Map<String, dynamic>? payload;
  final String? sessionId;
  final DateTime expiresAt;

  const GameInvite({
    required this.id,
    required this.boxId,
    required this.gameId,
    required this.sessionType,
    required this.inviterId,
    required this.inviteeId,
    required this.status,
    this.payload,
    this.sessionId,
    required this.expiresAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isExpired => status == 'expired';

  factory GameInvite.fromJson(Map<String, dynamic> json) => GameInvite(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        gameId: json['game_id'] as String,
        sessionType: json['session_type'] as String,
        inviterId: json['inviter_id'] as String,
        inviteeId: json['invitee_id'] as String,
        status: json['status'] as String,
        payload: json['payload'] as Map<String, dynamic>?,
        sessionId: json['session_id'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}
