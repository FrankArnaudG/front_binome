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
  // Voir demande utilisateur : "le bouton choisir doit changer et dire
  // carte de défi envoyée et non cliquable" — rempli une fois la carte
  // promise réellement envoyée (voir GameCardController::send), un lien
  // persistant plutôt qu'un simple état local éphémère.
  final String? gameCardSendId;
  // Boîte (thème) d'origine — renseigné seulement quand cette demande est
  // elle-même la RACINE d'un fil (voir GameBoxesScreen._openTruthOrDareBox),
  // `null` quand elle est envoyée en réponse dans un fil déjà ouvert (le
  // thème vient alors de la racine du fil, pas de la demande). Sert à
  // GameConversationsScreen pour retrouver quelle boîte rouvrir.
  final String? gameBoxId;

  const TruthOrDareRequest({
    required this.id,
    required this.gameId,
    required this.requesterId,
    required this.responderId,
    required this.status,
    this.chosenCategory,
    this.gameCardSendId,
    this.gameBoxId,
  });

  bool get isPending => status == 'pending';
  bool get isAnswered => status == 'answered';
  bool get isDefi => chosenCategory == 'defi';
  bool get isVerite => chosenCategory == 'verite';
  bool get isFulfilled => gameCardSendId != null;

  factory TruthOrDareRequest.fromJson(Map<String, dynamic> json) => TruthOrDareRequest(
        id: json['id'] as String,
        gameId: json['game_id'] as String,
        requesterId: json['requester_id'] as String,
        responderId: json['responder_id'] as String,
        status: json['status'] as String,
        chosenCategory: json['chosen_category'] as String?,
        gameCardSendId: json['game_card_send_id'] as String?,
        gameBoxId: json['game_box_id'] as String?,
      );

  TruthOrDareRequest copyWith({String? status, String? chosenCategory, String? gameCardSendId}) => TruthOrDareRequest(
        id: id,
        gameId: gameId,
        requesterId: requesterId,
        responderId: responderId,
        status: status ?? this.status,
        chosenCategory: chosenCategory ?? this.chosenCategory,
        gameCardSendId: gameCardSendId ?? this.gameCardSendId,
        gameBoxId: gameBoxId,
      );
}
