import 'app_user.dart';

/// Émojis proposés pour réagir à un envoi — pas de liste blanche stricte
/// côté backend (juste une chaîne validée), donc ceci est purement le choix
/// éditorial affiché dans [_ReactionBar] : le nécessaire pour un couple,
/// pas un clavier d'émojis complet.
const List<String> kSendReactionEmojis = [
  '❤️', '😍', '🥰', '😘', '😂', '🤣', '😮', '😢',
  '🥲', '👏', '🙌', '🔥', '💯', '🤔', '💭', '🎉',
  '🙏', '😴', '😡', '🤗',
];

/// Même principe, mais pour "Le Portrait Chinois" (voir GameCardThreadScreen)
/// — un jeu où on se DÉCOUVRE à travers des métaphores ("Si j'étais... je
/// serais"), le set générique ne collait pas complètement à cet esprit de
/// révélation/surprise : garde ses 3 émojis propres (masque, étincelles,
/// mind-blown) en tête, puis le même éventail élargi que [kSendReactionEmojis].
const List<String> kPortraitChinoisReactionEmojis = [
  '🎭', '✨', '🤯',
  '❤️', '😍', '🥰', '😘', '😂', '🤣', '😮', '😢',
  '🥲', '👏', '🙌', '🔥', '💯', '🤔', '💭', '🎉',
  '🙏', '😴', '😡', '🤗',
];

class SendReaction {
  final String id;
  final String sendId;
  final String userId;
  final String emoji;
  final DateTime createdAt;
  final AppUser? user;

  const SendReaction({
    required this.id,
    required this.sendId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
    this.user,
  });

  factory SendReaction.fromJson(Map<String, dynamic> json) => SendReaction(
        id: json['id'] as String,
        sendId: json['send_id'] as String,
        userId: json['user_id'] as String,
        emoji: json['emoji'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        user: json['user'] != null ? AppUser.fromJson(json['user'] as Map<String, dynamic>) : null,
      );
}
