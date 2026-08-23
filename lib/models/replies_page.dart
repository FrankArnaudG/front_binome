import 'send.dart';

/// Une page du fil de discussion d'un envoi (voir
/// ContentService.fetchReplies/SendController::replies) — les plus récentes
/// d'abord, avec [hasMore] pour savoir si des réponses plus anciennes
/// restent à charger.
class RepliesPage {
  final List<Send> items;
  final bool hasMore;

  const RepliesPage({required this.items, required this.hasMore});

  factory RepliesPage.fromJson(Map<String, dynamic> json) => RepliesPage(
        items: (json['items'] as List)
            .map((e) => Send.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: json['has_more'] as bool? ?? false,
      );
}
