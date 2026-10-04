import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_router.dart';
import '../../core/token_storage.dart';
import '../../models/app_user.dart';
import '../../models/send.dart';
import '../content/slide_detail_screen.dart';
import 'emoji_story_session_screen.dart';
import 'game_box_history_screen.dart';
import 'game_card_inbox_service.dart';
import 'game_card_received_screen.dart';
import 'game_service.dart';

/// Icône représentative du type d'envoi — cohérente partout où un envoi en
/// attente est représenté (bulle GameCardBubble, bannière InboxToast, liste
/// de choix quand plusieurs attendent).
IconData iconForPendingSend(Send send) {
  if (send.isEmojiStory) return Icons.emoji_emotions_rounded;
  if (send.isPack) return Icons.auto_stories_rounded;
  if (send.isHeartbeat) return Icons.favorite_rounded;
  if (send.isTruthOrDareRequest) return Icons.psychology_alt_rounded;
  return Icons.style_rounded;
}

/// Aperçu textuel court — même logique partout (bulle, bannière, liste).
String previewForPendingSend(Send send, String localeCode) {
  if (send.isEmojiStory) return send.emojiStory?.emojis ?? '💬';
  if (send.isPack) return send.pack?.titleFor(localeCode) ?? 'Un poème';
  if (send.isHeartbeat) return send.heartbeatMessageFor(localeCode) ?? 'Un cœur qui bat pour toi 💓';
  if (send.isTruthOrDareRequest) return 'Choisis Vérité ou Défi';
  return send.gameCard?.questionTextFor(localeCode) ?? 'Une question';
}

/// Ouvre la vraie discussion concernée par un envoi en attente — carte-
/// question (voir GameCardThreadScreen), story en émojis, poème-slide ou
/// battement de cœur (les deux derniers via SlideDetailScreen, le même
/// écran que le Carnet de bord). Utilisée à la fois par GameCardBubble (tap
/// sur la bulle persistante) et InboxToast (tap sur la bannière temporaire
/// qui s'ouvre à l'arrivée d'un nouvel envoi) — une seule logique de
/// navigation, jamais dupliquée. Retire l'envoi du badge juste avant de
/// pousser l'écran (succès ou repli), jamais avant — laisse l'appelant
/// afficher un indicateur de chargement pendant l'aller-retour réseau
/// (carte-question : besoin du Game/GameBox complets, pas juste leurs ids).
Future<void> openPendingSend(Send send) async {
  if (send.isEmojiStory) {
    // Pas de fil dédié à CETTE story précise (voir EmojiStorySessionScreen,
    // toutes les stories du jeu vivent dans la même discussion) — ouvre le
    // jeu en entier, la bulle concernée y est déjà visible.
    final emojiStory = send.emojiStory;
    if (emojiStory == null) {
      GameCardInboxService.instance.removePending(send.id);
      return;
    }
    try {
      final userJson = await TokenStorage.instance.readUserJson();
      if (userJson == null) throw StateError('Utilisateur introuvable.');
      final user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);

      final games = await GameService.instance.fetchGames();
      final gameMatches = games.where((g) => g.id == emojiStory.gameId);
      final game = gameMatches.isEmpty ? null : gameMatches.first;
      if (game == null) throw StateError('Jeu introuvable.');

      GameCardInboxService.instance.removePending(send.id);
      AppRouter.showGlobalNavBar.value = false;
      AppRouter.navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => EmojiStorySessionScreen(game: game, user: user)),
      );
    } catch (_) {
      GameCardInboxService.instance.removePending(send.id);
    }
    return;
  }

  if (send.isPack || send.isHeartbeat) {
    // Même écran que le Carnet de bord (voir TimelineScreen._openSend).
    try {
      final userJson = await TokenStorage.instance.readUserJson();
      if (userJson == null) throw StateError('Utilisateur introuvable.');
      final user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);

      GameCardInboxService.instance.removePending(send.id);
      AppRouter.navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => SlideDetailScreen(send: send, isMine: false, user: user)),
      );
    } catch (_) {
      GameCardInboxService.instance.removePending(send.id);
    }
    return;
  }

  final gameCard = send.gameCard;
  // Voir demande utilisateur : une demande "Vérité ou Défi" reçue (sans
  // carte encore piochée, voir TruthOrDareRequest) doit s'ouvrir comme
  // n'importe quel autre envoi en attente — le jeu/la boîte se résolvent
  // alors depuis la demande elle-même plutôt que depuis une carte qui
  // n'existe pas encore (voir GameConversationsScreen._open, même repli).
  final gameId = gameCard?.gameId ?? send.truthOrDareRequest?.gameId;
  final gameBoxId = gameCard?.gameBoxId ?? send.truthOrDareRequest?.gameBoxId;
  if (gameId == null || gameBoxId == null) {
    GameCardInboxService.instance.removePending(send.id);
    return;
  }

  try {
    final userJson = await TokenStorage.instance.readUserJson();
    if (userJson == null) throw StateError('Utilisateur introuvable.');
    final user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);

    final games = await GameService.instance.fetchGames();
    final gameMatches = games.where((g) => g.id == gameId);
    final game = gameMatches.isEmpty ? null : gameMatches.first;

    final boxes = await GameService.instance.fetchBoxes(gameId);
    final boxMatches = boxes.where((b) => b.id == gameBoxId);
    final box = boxMatches.isEmpty ? null : boxMatches.first;

    if (game == null || box == null) throw StateError('Boîte de jeu introuvable.');

    GameCardInboxService.instance.removePending(send.id);
    AppRouter.showGlobalNavBar.value = false;
    AppRouter.navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => GameCardThreadScreen(send: send, user: user, game: game, box: box)),
    );
  } catch (_) {
    GameCardInboxService.instance.removePending(send.id);
    AppRouter.navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => GameCardReceivedScreen(send: send)),
    );
  }
}
