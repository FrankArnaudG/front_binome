import 'send.dart';

/// Une discussion "Devine mon émoji" (voir EmojiStoryController::sessions)
/// — plusieurs stories échangées librement dans le même fil au fil du
/// temps, exactement comme se comportait l'ancien fil unique du jeu. Un
/// couple peut désormais avoir plusieurs de ces discussions séparées (voir
/// EmojiStoryHistoryScreen, qui les liste par activité la plus récente).
class EmojiStorySession {
  final String id;
  final String gameId;
  final DateTime lastActivityAt;
  // La story la plus récente de cette discussion — sert d'aperçu dans
  // EmojiStoryHistoryScreen sans charger tout l'historique de la discussion.
  final Send latestSend;

  const EmojiStorySession({
    required this.id,
    required this.gameId,
    required this.lastActivityAt,
    required this.latestSend,
  });

  factory EmojiStorySession.fromJson(Map<String, dynamic> json) => EmojiStorySession(
        id: json['id'] as String,
        gameId: json['game_id'] as String,
        lastActivityAt: DateTime.parse(json['last_activity_at'] as String),
        latestSend: Send.fromJson(json['latest_send'] as Map<String, dynamic>),
      );
}

/// Une page de la liste des discussions (voir RepliesPage, même forme pour
/// la pagination des réponses d'un fil) — les plus actives d'abord, avec
/// [hasMore] pour savoir si des discussions plus anciennes restent à charger.
class EmojiStorySessionsPage {
  final List<EmojiStorySession> items;
  final bool hasMore;

  const EmojiStorySessionsPage({required this.items, required this.hasMore});

  factory EmojiStorySessionsPage.fromJson(Map<String, dynamic> json) => EmojiStorySessionsPage(
        items: (json['items'] as List)
            .map((e) => EmojiStorySession.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: json['has_more'] as bool? ?? false,
      );
}
