import 'app_user.dart';
import 'emoji_story_send.dart';
import 'game_card_send.dart';
import 'gift.dart';
import 'heartbeat_image.dart';
import 'pack.dart';
import 'send_reaction.dart';
import 'slide.dart';

// STX/ETX (caractères de contrôle qu'aucun clavier/IME ne produit jamais) —
// voir GameCardThreadScreen._encodeQuoted/_decodeQuoted, qui encode une
// citation "Répondre à..." directement dans le texte d'un message plutôt
// que via un champ serveur dédié. Repris ici (String.fromCharCode plutôt
// qu'un caractère littéral, invisible et donc fragile à l'édition) pour que
// shortPreview (liste de discussions) affiche seulement le VRAI texte du
// message, jamais la citation encodée (voir demande utilisateur : "ignorer
// le commentaire et mettre juste le message").
final String _quoteStart = String.fromCharCode(2);
final String _quoteEnd = String.fromCharCode(3);

String _withoutQuotedPrefix(String raw) {
  if (raw.startsWith(_quoteStart)) {
    final endIndex = raw.indexOf(_quoteEnd);
    if (endIndex != -1) return raw.substring(endIndex + 1);
  }
  return raw;
}

class Send {
  final String id;
  final String boxId;
  final String senderId;
  final String recipientId;
  final String sendableType; // pack | slide | gift | heartbeat | game_card
  final String? replyToSendId;
  final String? message;
  final int coinCost;
  final String status; // sent | delivered | seen
  final bool isFavorite;
  final DateTime? seenAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final AppUser? sender;
  final AppUser? recipient;
  final Pack? pack;
  final Slide? slide;
  final Gift? gift;
  final Map<String, String>? heartbeatMessage;
  final List<HeartbeatImage> heartbeatImages;
  final GameCardSend? gameCard;
  final EmojiStorySend? emojiStory;
  final String? emojiReplyText;
  final String? textReplyText;
  final List<SendReaction> reactions;
  final Send? replyTo;
  // Le message le plus récent de cette discussion (voir Send::latestReply
  // côté backend) — `null` tant qu'aucune réponse n'a encore été envoyée,
  // auquel cas cet envoi (le message d'ouverture) EST le dernier message.
  // Utilisé par les listes de discussions (Carnet de bord, historique de
  // boîte de jeu) pour afficher un aperçu à jour plutôt que figé sur
  // l'ouverture — voir Send.lastMessage.
  final Send? latestReply;

  const Send({
    required this.id,
    required this.boxId,
    required this.senderId,
    required this.recipientId,
    required this.sendableType,
    this.replyToSendId,
    this.message,
    required this.coinCost,
    required this.status,
    this.isFavorite = false,
    this.seenAt,
    this.deliveredAt,
    required this.createdAt,
    this.sender,
    this.recipient,
    this.pack,
    this.slide,
    this.gift,
    this.heartbeatMessage,
    this.heartbeatImages = const [],
    this.gameCard,
    this.emojiStory,
    this.emojiReplyText,
    this.textReplyText,
    this.reactions = const [],
    this.replyTo,
    this.latestReply,
  });

  factory Send.fromJson(Map<String, dynamic> json) => Send(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        senderId: json['sender_id'] as String,
        recipientId: json['recipient_id'] as String,
        sendableType: json['sendable_type'] as String,
        replyToSendId: json['reply_to_send_id'] as String?,
        message: json['message'] as String?,
        coinCost: json['coin_cost'] as int? ?? 0,
        status: json['status'] as String,
        isFavorite: json['is_favorite'] as bool? ?? false,
        seenAt: json['seen_at'] != null ? DateTime.parse(json['seen_at'] as String) : null,
        deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        sender: json['sender'] != null ? AppUser.fromJson(json['sender'] as Map<String, dynamic>) : null,
        recipient: json['recipient'] != null ? AppUser.fromJson(json['recipient'] as Map<String, dynamic>) : null,
        pack: json['sendable_type'] == 'pack' && json['sendable'] != null
            ? Pack.fromJson(json['sendable'] as Map<String, dynamic>)
            : null,
        slide: json['sendable_type'] == 'slide' && json['sendable'] != null
            ? Slide.fromJson(json['sendable'] as Map<String, dynamic>)
            : null,
        gift: json['sendable_type'] == 'gift' && json['sendable'] != null
            ? Gift.fromJson(json['sendable'] as Map<String, dynamic>)
            : null,
        heartbeatMessage: json['sendable_type'] == 'heartbeat' && json['sendable'] != null
            ? _localeMap((json['sendable'] as Map<String, dynamic>)['message'])
            : null,
        heartbeatImages: json['sendable_type'] == 'heartbeat' && json['sendable'] != null
            ? ((json['sendable'] as Map<String, dynamic>)['images'] as List<dynamic>? ?? const [])
                .map((e) => HeartbeatImage.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
        gameCard: json['sendable_type'] == 'game_card' && json['sendable'] != null
            ? GameCardSend.fromJson(json['sendable'] as Map<String, dynamic>)
            : null,
        emojiStory: json['sendable_type'] == 'emoji_story' && json['sendable'] != null
            ? EmojiStorySend.fromJson(json['sendable'] as Map<String, dynamic>)
            : null,
        emojiReplyText: json['sendable_type'] == 'emoji_reply' && json['sendable'] != null
            ? (json['sendable'] as Map<String, dynamic>)['emojis'] as String?
            : null,
        textReplyText: json['sendable_type'] == 'text_reply' && json['sendable'] != null
            ? (json['sendable'] as Map<String, dynamic>)['text'] as String?
            : null,
        reactions: json['reactions'] != null
            ? (json['reactions'] as List)
                .map((e) => SendReaction.fromJson(e as Map<String, dynamic>))
                .toList()
            : const [],
        replyTo: json['reply_to'] != null
            ? Send.fromJson(json['reply_to'] as Map<String, dynamic>)
            : null,
        latestReply: json['latest_reply'] != null
            ? Send.fromJson(json['latest_reply'] as Map<String, dynamic>)
            : null,
      );

  /// Utile pour intégrer une mise à jour reçue en direct (voir
  /// RealtimeClient) sans repartir d'un fetch complet — [status]/[seenAt]
  /// pour le double-check "lu" façon WhatsApp (voir SendSeen côté backend),
  /// [reactions] pour le reste, [latestReply] pour qu'une liste de
  /// discussions (Carnet de bord, historique de boîte de jeu) mette à jour
  /// l'aperçu d'une discussion existante dès qu'une réponse y arrive en
  /// direct, sans re-fetch complet — voir GameBoxHistoryScreen._onRealtimeEvent.
  Send copyWith({
    List<SendReaction>? reactions,
    String? status,
    DateTime? seenAt,
    DateTime? deliveredAt,
    Send? latestReply,
    GameCardSend? gameCard,
  }) =>
      Send(
        id: id,
        boxId: boxId,
        senderId: senderId,
        recipientId: recipientId,
        sendableType: sendableType,
        replyToSendId: replyToSendId,
        message: message,
        coinCost: coinCost,
        status: status ?? this.status,
        isFavorite: isFavorite,
        seenAt: seenAt ?? this.seenAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        createdAt: createdAt,
        sender: sender,
        recipient: recipient,
        pack: pack,
        slide: slide,
        gift: gift,
        heartbeatMessage: heartbeatMessage,
        heartbeatImages: heartbeatImages,
        gameCard: gameCard ?? this.gameCard,
        emojiStory: emojiStory,
        emojiReplyText: emojiReplyText,
        textReplyText: textReplyText,
        reactions: reactions ?? this.reactions,
        replyTo: replyTo,
        latestReply: latestReply ?? this.latestReply,
      );

  bool get isSeen => status == 'seen';
  bool get isDelivered => status == 'delivered' || status == 'seen';
  bool get isPack => sendableType == 'pack';
  bool get isGift => sendableType == 'gift';
  bool get isHeartbeat => sendableType == 'heartbeat';
  bool get isGameCard => sendableType == 'game_card';
  bool get isEmojiStory => sendableType == 'emoji_story';
  bool get isEmojiReply => sendableType == 'emoji_reply';
  bool get isTextReply => sendableType == 'text_reply';
  bool get isReply => replyToSendId != null;

  /// Le message effectif à afficher dans une liste de discussions : le
  /// dernier échange s'il y en a un (voir latestReply), sinon ce message
  /// d'ouverture lui-même.
  Send get lastMessage => latestReply ?? this;

  /// Aperçu textuel court d'UN envoi précis, tous types confondus — pensé
  /// pour être appelé sur `lastMessage`, jamais directement sur un envoi
  /// racine dont on ignorerait les réponses (voir previewForPendingSend,
  /// qui ne couvre lui que les envois encore SANS réponse). Prend le code
  /// de langue courant en paramètre (plutôt qu'un getter sans contexte) car
  /// pack.title est désormais une carte multilingue à résoudre.
  String shortPreview(String localeCode) {
    if (isGameCard) return gameCard?.questionTextFor(localeCode) ?? 'Une question';
    if (isPack) return pack?.titleFor(localeCode) ?? 'Un poème';
    if (isGift) return gift?.name ?? 'Un cadeau';
    if (isHeartbeat) return heartbeatMessageFor(localeCode) ?? 'Un cœur qui bat pour toi 💓';
    if (isEmojiStory) return emojiStory?.emojis ?? '💬';
    if (isEmojiReply) return emojiReplyText ?? '💬';
    // Ignore la citation éventuellement encodée dans le texte (voir
    // _withoutQuotedPrefix) — seul le vrai message compte dans un aperçu
    // de liste (voir demande utilisateur).
    if (isTextReply) return _withoutQuotedPrefix(textReplyText ?? '');
    return '';
  }

  String? heartbeatMessageFor(String localeCode) =>
      heartbeatMessage?[localeCode] ?? heartbeatMessage?['fr'];

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}
