/// Une demande "choisis Vérité ou Défi" — voir TruthOrDareRequestController
/// côté backend. [status] : `pending` (en attente de la réponse de
/// [responderId]) ou `answered` (voir [chosenCategory]).
class TruthOrDareRequest {
  final String id;
  final String gameId;
  final String requesterId;
  final String responderId;
  final String status;
  final String? chosenCategory; // 'verite' | 'defi' | null tant que pending

  const TruthOrDareRequest({
    required this.id,
    required this.gameId,
    required this.requesterId,
    required this.responderId,
    required this.status,
    this.chosenCategory,
  });

  bool get isPending => status == 'pending';
  bool get isAnswered => status == 'answered';
  bool get isDefi => chosenCategory == 'defi';
  bool get isVerite => chosenCategory == 'verite';

  factory TruthOrDareRequest.fromJson(Map<String, dynamic> json) => TruthOrDareRequest(
        id: json['id'] as String,
        gameId: json['game_id'] as String,
        requesterId: json['requester_id'] as String,
        responderId: json['responder_id'] as String,
        status: json['status'] as String,
        chosenCategory: json['chosen_category'] as String?,
      );

  TruthOrDareRequest copyWith({String? status, String? chosenCategory}) => TruthOrDareRequest(
        id: id,
        gameId: gameId,
        requesterId: requesterId,
        responderId: responderId,
        status: status ?? this.status,
        chosenCategory: chosenCategory ?? this.chosenCategory,
      );
}
