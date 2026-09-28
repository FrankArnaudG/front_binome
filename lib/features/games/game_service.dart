import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/dot_square_session.dart';
import '../../models/emoji_story_session.dart';
import '../../models/game_invite.dart';
import '../../models/battleship_session.dart';
import '../../models/number_hunt_session.dart';
import '../../models/war_card_session.dart';
import '../../models/emoji_story_stats.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../models/game_card_send.dart';
import '../../models/memory_game_session.dart';
import '../../models/memory_game_stats.dart';
import '../../models/public_profile.dart';
import '../../models/replies_page.dart';
import '../../models/send.dart';
import '../../models/suit_battle_session.dart';
import '../../models/tic_tac_toe_session.dart';

class GameService {
  GameService._();
  static final GameService instance = GameService._();

  Future<List<Game>> fetchGames() async {
    final data = await ApiClient.instance.get('/games') as List;
    return data.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Taux de décompte en pièces des jeux interactifs (voir demande
  /// utilisateur : afficher "1 pièce = X minutes" sur l'écran de choix du
  /// mode "à distance") — mis en cache en mémoire pour cette session, pas
  /// besoin de re-fetch à chaque écran ouvert (ce réglage change rarement).
  Map<String, int>? _cachedEconomyRate;

  Future<Map<String, int>> fetchGameEconomyRate() async {
    final cached = _cachedEconomyRate;
    if (cached != null) return cached;
    final data = await ApiClient.instance.get('/game-economy-rate') as Map<String, dynamic>;
    final rate = {
      'minutes_per_coin': data['minutes_per_coin'] as int? ?? 8,
      'grace_period_seconds': data['grace_period_seconds'] as int? ?? 0,
      'nearby_daily_coin_cost': data['nearby_daily_coin_cost'] as int? ?? 5,
      'nearby_free_trial_days': data['nearby_free_trial_days'] as int? ?? 3,
    };
    _cachedEconomyRate = rate;
    return rate;
  }

  /// Dernière liste connue de boîtes pour ce jeu (voir LocalCache), sans
  /// appel réseau — permet à GameBoxesScreen de s'afficher instantanément
  /// au lieu d'un loader à chaque ouverture. `null` si jamais mise en cache.
  Future<List<GameBox>?> cachedBoxes(String gameId) async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>('cache_game_boxes_$gameId');
    if (cached == null) return null;
    return cached.map((e) => GameBox.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Vide pour un jeu sans boîtes (voir GameSessionScreen, le gabarit à
  /// prompt unique utilisé par défaut tant qu'un jeu n'a pas de contenu ici.
  /// Mis en cache comme fetchBoxHistory/fetchCardInbox — repli sur la
  /// dernière liste connue si le réseau échoue.
  Future<List<GameBox>> fetchBoxes(String gameId) async {
    final cacheKey = 'cache_game_boxes_$gameId';
    try {
      final data = await ApiClient.instance.get('/games/$gameId/boxes') as List;
      await LocalCache.instance.writeJson(cacheKey, data);
      return data.map((e) => GameBox.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      final cached = await LocalCache.instance.readJson<List<dynamic>>(cacheKey);
      if (cached != null) {
        return cached.map((entry) => GameBox.fromJson(entry as Map<String, dynamic>)).toList();
      }
      rethrow;
    }
  }

  Future<void> completeBox(String gameId, String gameBoxId) {
    return ApiClient.instance.post('/games/$gameId/boxes/$gameBoxId/complete');
  }

  /// Voir GameSessionLifecycleController::close et demande utilisateur :
  /// ferme VRAIMENT une session déjà terminée (arrête micro/caméra/chrono/
  /// facturation pour les DEUX) — jamais appelé pendant une partie encore
  /// en cours, seulement quand on quitte l'écran de score, quel que soit
  /// le moyen (bouton "Quitter", tap à côté, retour arrière...). Best-
  /// effort volontaire (voir les appelants) : un raté ici n'empêche jamais
  /// de quitter, le filet des 30 min d'inactivité côté serveur reprend le
  /// relais (voir BillGameSessions).
  Future<void> closeGameSession(String sessionType, String sessionId) {
    return ApiClient.instance.post('/game-sessions/$sessionType/$sessionId/close');
  }

  /// Voir GameSessionLifecycleController::micPing et demande utilisateur :
  /// repousse de 30 min la coupure automatique de la session — à appeler
  /// UNIQUEMENT quand SON PROPRE micro passe au vert APRÈS la fin de la
  /// manche (voir VoiceCallOverlay.onMicActiveChanged), jamais pendant une
  /// partie encore en cours.
  Future<void> pingGameSessionMic(String sessionType, String sessionId) {
    return ApiClient.instance.post('/game-sessions/$sessionType/$sessionId/mic-ping');
  }

  /// Envoie une carte-question précise au/à la partenaire (voir
  /// GameCardController::send côté backend).
  /// [replyToSendId] : envoyée depuis la bulle "Envoyer une autre carte"
  /// d'une discussion déjà ouverte (voir GameCardThreadScreen) — la carte
  /// rejoint alors CETTE discussion comme un nouveau message plutôt que
  /// d'en ouvrir une nouvelle.
  /// [senderAnswer] : réservé à "Le Sondage Surprise" (session_type =
  /// 'blind_poll', voir Game.isBlindPoll) — la réponse cachée choisie par
  /// qui envoie, au moment de l'envoi (voir GameCardController::send).
  /// Ignoré (et non requis) pour tous les autres jeux à boîtes.
  Future<Send> sendCard(
    String gameId,
    String gameBoxId,
    String questionId, {
    String? replyToSendId,
    String? senderAnswer,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/boxes/$gameBoxId/questions/$questionId/send',
      body: {
        if (replyToSendId != null) 'reply_to_send_id': replyToSendId,
        if (senderAnswer != null) 'sender_answer': senderAnswer,
      },
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  Future<GameCardSendUpdate> answerCard(String cardSendId, String answer) async {
    final data = await ApiClient.instance.put(
      '/game-card-sends/$cardSendId/answer',
      body: {'answer': answer},
    ) as Map<String, dynamic>;
    return GameCardSendUpdate.fromJson(data);
  }

  /// Réponse à une carte "Le Sondage Surprise" — même route que answerCard,
  /// mais renvoie la carte complète (sender_answer/answer/options) pour
  /// afficher la révélation tout de suite sans attendre un aller-retour
  /// temps réel (voir GameCardThreadScreen._submitBlindPollAnswer).
  Future<GameCardSend> answerBlindPoll(String cardSendId, String answer) async {
    final data = await ApiClient.instance.put(
      '/game-card-sends/$cardSendId/answer',
      body: {'answer': answer},
    ) as Map<String, dynamic>;
    return GameCardSend.fromJson(data);
  }

  /// Modifie MA réponse cachée d'une carte "Le Sondage Surprise" que j'ai
  /// envoyée, tant que mon binôme n'a pas encore répondu à son tour (voir
  /// GameCardThreadScreen._buildPollWaitingBubble) — le backend refuse dès
  /// que sa réponse est arrivée (voir GameCardController::updateSenderAnswer).
  Future<GameCardSend> updateBlindPollSenderAnswer(String cardSendId, String answer) async {
    final data = await ApiClient.instance.put(
      '/game-card-sends/$cardSendId/blind-poll-answer',
      body: {'answer': answer},
    ) as Map<String, dynamic>;
    return GameCardSend.fromJson(data);
  }

  /// Invite qui a envoyé la carte à répondre lui/elle aussi à la même
  /// question ("Ai-je le droit ?"/"Sans Détour" uniquement, voir
  /// GameCardController::inviteSender) — déclenché par qui a déjà répondu.
  Future<GameCardSend> inviteSenderToAnswer(String cardSendId) async {
    final data = await ApiClient.instance.put('/game-card-sends/$cardSendId/invite-sender') as Map<String, dynamic>;
    return GameCardSend.fromJson(data);
  }

  /// Réponse de qui a envoyé la carte, après avoir été invité·e (voir
  /// inviteSenderToAnswer ci-dessus) — pose sender_answer après coup.
  Future<GameCardSend> answerAsSender(String cardSendId, String answer) async {
    final data = await ApiClient.instance.put(
      '/game-card-sends/$cardSendId/sender-answer',
      body: {'answer': answer},
    ) as Map<String, dynamic>;
    return GameCardSend.fromJson(data);
  }

  /// "Retourne" la carte à qui l'a envoyée — crée un nouvel envoi dans
  /// l'autre sens, avec la même question.
  Future<Send> bounceCard(String cardSendId) async {
    final data = await ApiClient.instance.post('/game-card-sends/$cardSendId/bounce') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Propose une devinette suivante (après une réponse fausse avec une
  /// nouvelle chance, voir submitCardVerdict) — réservé aux jeux
  /// `session_type = 'quiz'` (voir Game.isQuiz). La toute première tentative
  /// passe toujours par answerCard, pas par ici (voir
  /// GameCardController::guess).
  Future<Send> guessCard(String cardSendId, String guess) async {
    final data = await ApiClient.instance.put(
      '/game-card-sends/$cardSendId/guess',
      body: {'guess': guess},
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Confirme ou infirme la dernière devinette en attente pour une carte
  /// `quiz` — copie conforme de submitEmojiStoryVerdict.
  Future<Send> submitCardVerdict(
    String cardSendId, {
    required bool correct,
    bool? retry,
    String? reveal,
  }) async {
    final data = await ApiClient.instance.put(
      '/game-card-sends/$cardSendId/verdict',
      body: {
        'correct': correct,
        if (!correct) 'retry': retry ?? false,
        if (reveal != null && reveal.isNotEmpty) 'reveal': reveal,
      },
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Dernier score "match" connu du jeu quiz courant (voir LocalCache), sans
  /// appel réseau.
  Future<EmojiStoryMatchStats?> cachedQuizStats(String gameId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_quiz_stats_$gameId');
    if (cached == null) return null;
    return EmojiStoryMatchStats.fromJson(cached);
  }

  /// Score "façon match" des deux membres du couple pour un jeu
  /// `session_type = 'quiz'` (voir GameCardController::stats) — même forme
  /// que fetchEmojiStoryStats, réutilise donc directement EmojiStoryMatchStats
  /// plutôt que de dupliquer un modèle identique.
  Future<EmojiStoryMatchStats> fetchQuizStats(String gameId) async {
    final cacheKey = 'cache_quiz_stats_$gameId';
    try {
      final data = await ApiClient.instance.get('/games/$gameId/quiz-stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return EmojiStoryMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return EmojiStoryMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Dernière PREMIÈRE page connue pour cette boîte (voir LocalCache), sans
  /// appel réseau — permet à GameBoxHistoryScreen de s'afficher
  /// instantanément au lieu d'un écran vide le temps du premier fetch.
  /// `null` si jamais mise en cache. Seule la première page (les 20 plus
  /// récentes) est mise en cache, comme ContentService.fetchReplies — une
  /// boîte peut accumuler beaucoup de cartes, remonter plus loin dans
  /// l'historique nécessite déjà une connexion.
  Future<RepliesPage?> cachedBoxHistory(String gameBoxId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_game_box_history_$gameBoxId');
    if (cached == null) return null;
    return RepliesPage.fromJson(cached);
  }

  /// Historique (envoyées + réponses + relances) d'une boîte, tous membres
  /// du couple confondus — alimente le fil de discussion ouvert depuis
  /// l'éventail de cartes (voir GameCardController::history). Paginé (les
  /// plus récentes d'abord, [beforeId] pour remonter plus loin) comme
  /// ContentService.fetchReplies — [limit] par défaut à 20, seule la
  /// première page (sans [beforeId]) est mise en cache.
  Future<RepliesPage> fetchBoxHistory(String gameId, String gameBoxId, {String? beforeId, int limit = 20}) async {
    final query = {
      'limit': '$limit',
      if (beforeId != null) 'before': beforeId,
    };
    final uri = Uri(path: '/games/$gameId/boxes/$gameBoxId/history', queryParameters: query);
    final cacheKey = 'cache_game_box_history_$gameBoxId';

    try {
      final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
      final page = RepliesPage.fromJson(data);
      if (beforeId == null) await LocalCache.instance.writeJson(cacheKey, data);
      return page;
    } catch (e) {
      if (beforeId == null) {
        final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) return RepliesPage.fromJson(cached);
      }
      rethrow;
    }
  }

  /// Dernière liste connue de la bulle de notification (voir LocalCache),
  /// sans appel réseau — pour qu'elle puisse s'afficher dès le lancement de
  /// l'app, avant même la réponse du serveur. `null` si jamais mise en cache.
  Future<List<Send>?> cachedCardInbox() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>('cache_game_card_inbox');
    if (cached == null) return null;
    return cached.map((e) => Send.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Envois en attente (cartes-questions ET stories en émojis) — alimente
  /// la bulle de notification unique (voir GameCardController::inbox). Mis
  /// en cache comme fetchBoxHistory ci-dessus.
  Future<List<Send>> fetchCardInbox() async {
    const cacheKey = 'cache_game_card_inbox';
    try {
      final data = await ApiClient.instance.get('/game-card-sends/inbox') as List;
      await LocalCache.instance.writeJson(cacheKey, data);
      return data.map((e) => Send.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      final cached = await LocalCache.instance.readJson<List<dynamic>>(cacheKey);
      if (cached != null) {
        return cached.map((entry) => Send.fromJson(entry as Map<String, dynamic>)).toList();
      }
      rethrow;
    }
  }

  /// Compose et envoie une story en émojis au/à la partenaire (voir
  /// EmojiStoryController::send) — [sessionId] rattache la story à une
  /// discussion déjà existante (continuer le même fil) ; omis, une nouvelle
  /// discussion est créée pour cette story (voir "Nouveau plan de jeu" dans
  /// EmojiStoryHistoryScreen). L'id de la discussion résultante se lit sur
  /// `send.emojiStory!.sessionId` — utile au tout premier envoi d'un fil
  /// vide, pour que les envois suivants du même écran s'y rattachent.
  Future<Send> sendEmojiStory(String gameId, String emojis, {String? sessionId}) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/emoji-stories/send',
      body: {'emojis': emojis, if (sessionId != null) 'session_id': sessionId},
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Propose une devinette — sert aussi bien la toute première tentative
  /// qu'une tentative suivante après une nouvelle chance donnée (voir
  /// submitEmojiStoryVerdict, [retry]) : c'est le même appel dans les deux
  /// cas, la story reste la MÊME bulle du début à la fin (voir
  /// EmojiStorySend).
  Future<Send> guessEmojiStory(String storySendId, String guess) async {
    final data = await ApiClient.instance.put(
      '/emoji-story-sends/$storySendId/guess',
      body: {'guess': guess},
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Confirme ou infirme la devinette reçue. Si fausse, [retry] décide :
  /// redonner une chance (obligatoire à préciser dans ce cas, voir
  /// EmojiStoryController::verdict) ou clore la story sans qu'elle ait été
  /// devinée, avec une révélation optionnelle.
  Future<Send> submitEmojiStoryVerdict(
    String storySendId, {
    required bool correct,
    bool? retry,
    String? reveal,
  }) async {
    final data = await ApiClient.instance.put(
      '/emoji-story-sends/$storySendId/verdict',
      body: {
        'correct': correct,
        if (!correct) 'retry': retry ?? false,
        if (reveal != null && reveal.isNotEmpty) 'reveal': reveal,
      },
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Modifie les émojis d'une story déjà envoyée (voir
  /// EmojiStoryController::update) — uniquement qui l'a composée.
  Future<Send> editEmojiStory(String storySendId, String emojis) async {
    final data = await ApiClient.instance.put(
      '/emoji-story-sends/$storySendId',
      body: {'emojis': emojis},
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Supprime (suppression douce, voir EmojiStoryController::destroy) une
  /// story déjà envoyée — la bulle reste dans le fil avec un repli "Story
  /// supprimée" côté Flutter plutôt que de disparaître.
  Future<Send> deleteEmojiStory(String storySendId) async {
    final data = await ApiClient.instance.delete('/emoji-story-sends/$storySendId') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Corrige MA devinette encore en attente de verdict (voir
  /// EmojiStoryController::updateGuess).
  Future<Send> editEmojiGuess(String guessId, String guess) async {
    final data = await ApiClient.instance.put(
      '/emoji-story-guesses/$guessId',
      body: {'guess': guess},
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Retire MA devinette encore en attente de verdict (voir
  /// EmojiStoryController::destroyGuess) — la story redevient disponible
  /// pour en proposer une nouvelle.
  Future<Send> deleteEmojiGuess(String guessId) async {
    final data = await ApiClient.instance.delete('/emoji-story-guesses/$guessId') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Dernière PREMIÈRE page connue de la liste des discussions (voir
  /// LocalCache), sans appel réseau — même principe que cachedBoxHistory.
  Future<EmojiStorySessionsPage?> cachedEmojiStorySessions(String gameId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_emoji_story_sessions_$gameId');
    if (cached == null) return null;
    return EmojiStorySessionsPage.fromJson(cached);
  }

  /// Discussions "Devine mon émoji" (voir EmojiStoryController::sessions),
  /// les plus actives d'abord — seule la première page (sans [beforeId])
  /// est mise en cache.
  Future<EmojiStorySessionsPage> fetchEmojiStorySessions(String gameId, {String? beforeId, int limit = 20}) async {
    final query = {
      'limit': '$limit',
      if (beforeId != null) 'before': beforeId,
    };
    final uri = Uri(path: '/games/$gameId/emoji-story-sessions', queryParameters: query);
    final cacheKey = 'cache_emoji_story_sessions_$gameId';

    try {
      final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
      final page = EmojiStorySessionsPage.fromJson(data);
      if (beforeId == null) await LocalCache.instance.writeJson(cacheKey, data);
      return page;
    } catch (e) {
      if (beforeId == null) {
        final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) return EmojiStorySessionsPage.fromJson(cached);
      }
      rethrow;
    }
  }

  /// Dernière PREMIÈRE page connue du fil d'UNE discussion (voir
  /// LocalCache), sans appel réseau.
  Future<RepliesPage?> cachedEmojiStoryHistory(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_emoji_story_history_$sessionId');
    if (cached == null) return null;
    return RepliesPage.fromJson(cached);
  }

  /// Fil des stories d'UNE discussion précise (voir
  /// EmojiStoryController::storyHistory) — UN SEUL Send par story (voir
  /// EmojiStorySend), donc la même forme paginée que fetchBoxHistory ;
  /// seule la première page (sans [beforeId]) est mise en cache.
  Future<RepliesPage> fetchEmojiStoryHistory(String gameId, String sessionId, {String? beforeId, int limit = 20}) async {
    final query = {
      'limit': '$limit',
      if (beforeId != null) 'before': beforeId,
    };
    final uri = Uri(path: '/games/$gameId/emoji-story-sessions/$sessionId/stories', queryParameters: query);
    final cacheKey = 'cache_emoji_story_history_$sessionId';

    try {
      final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
      final page = RepliesPage.fromJson(data);
      if (beforeId == null) await LocalCache.instance.writeJson(cacheKey, data);
      return page;
    } catch (e) {
      if (beforeId == null) {
        final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) return RepliesPage.fromJson(cached);
      }
      rethrow;
    }
  }

  /// Dernier score "match" connu d'UNE discussion (voir LocalCache), sans
  /// appel réseau.
  Future<EmojiStoryMatchStats?> cachedEmojiStoryStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_emoji_story_stats_$sessionId');
    if (cached == null) return null;
    return EmojiStoryMatchStats.fromJson(cached);
  }

  /// Score "façon match" des deux membres du couple pour UNE discussion
  /// précise (voir EmojiStoryController::stats) — le classement est propre
  /// à chaque "plan de jeu", jamais cumulé sur l'ensemble des discussions.
  Future<EmojiStoryMatchStats> fetchEmojiStoryStats(String gameId, String sessionId) async {
    final cacheKey = 'cache_emoji_story_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/games/$gameId/emoji-story-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return EmojiStoryMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return EmojiStoryMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Démarre une partie de "Jeu de Mémoire" à distance — [board] est déjà
  /// tiré et mélangé côté client depuis le pool de 60 émojis (voir
  /// memory_emoji_pool.dart) avant cet appel, le serveur le stocke tel
  /// quel comme source de vérité.
  Future<MemoryGameSession> startMemoryGame(String gameId, {required int pairCount, required List<String> board}) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/memory-sessions/start',
      body: {'pair_count': pairCount, 'board': board},
    ) as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  /// Retourne une carte — voir MemoryGameController::flip pour toute la
  /// résolution de tour (match/mismatch/changement de tour/fin de partie),
  /// l'état à jour arrive aussi bien ici qu'en temps réel via
  /// MemoryGameTransport (voir RealtimeClient).
  Future<MemoryGameSession> flipMemoryCard(String sessionId, int index) async {
    final data = await ApiClient.instance.put(
      '/memory-sessions/$sessionId/flip',
      body: {'index': index},
    ) as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  /// Resynchronisation après reprise d'app/reconnexion — jamais mis en
  /// cache, contrairement aux autres `fetchX`/`cachedX` de ce fichier :
  /// une partie en cours n'a pas de sens à afficher depuis un cliché
  /// obsolète, mieux vaut échouer franchement si hors-ligne.
  Future<MemoryGameSession> fetchMemoryGameState(String sessionId) async {
    final data = await ApiClient.instance.get('/memory-sessions/$sessionId') as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  Future<MemoryGameSession> abandonMemoryGame(String sessionId) async {
    final data = await ApiClient.instance.put('/memory-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  /// N'importe lequel des deux peut la déclencher — voir
  /// MemoryGameController::pause, seule cette personne pourra la lever.
  Future<MemoryGameSession> pauseMemoryGame(String sessionId) async {
    final data = await ApiClient.instance.put('/memory-sessions/$sessionId/pause') as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  /// Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
  /// MemoryGameController::resume).
  Future<MemoryGameSession> resumeMemoryGame(String sessionId) async {
    final data = await ApiClient.instance.put('/memory-sessions/$sessionId/resume') as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  Future<MemoryGameMatchStats?> cachedMemoryGameStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_memory_game_stats_$sessionId');
    if (cached == null) return null;
    return MemoryGameMatchStats.fromJson(cached);
  }

  Future<MemoryGameMatchStats> fetchMemoryGameStats(String sessionId) async {
    final cacheKey = 'cache_memory_game_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/memory-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return MemoryGameMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return MemoryGameMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté ou pass-and-play, voir
  /// MemoryGameTransport) — best-effort, appelé une seule fois par le
  /// périphérique "autoritaire" (l'hôte en Nearby, l'unique appareil en
  /// pass-and-play) pour garder un historique cohérent entre les 3 modes.
  Future<MemoryGameSession> recordMemoryGameResult(
    String gameId, {
    required int pairCount,
    required int movesCount,
    required int durationSeconds,
    required Map<String, int> pairsByUser,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/memory-results',
      body: {
        'pair_count': pairCount,
        'moves_count': movesCount,
        'duration_seconds': durationSeconds,
        'pairs_by_user': pairsByUser,
      },
    ) as Map<String, dynamic>;
    return MemoryGameSession.fromJson(data);
  }

  // "Morpion à Deux" — copie structurelle conforme des méthodes "Jeu de
  // Mémoire" juste au-dessus, même convention de nommage.

  Future<TicTacToeSession> startTicTacToe(String gameId) async {
    final data = await ApiClient.instance.post('/games/$gameId/tic-tac-toe-sessions/start') as Map<String, dynamic>;
    return TicTacToeSession.fromJson(data);
  }

  /// Pose ([from] `null`) ou déplace ([from] renseigné) un pion — voir
  /// TicTacToeController::move.
  Future<TicTacToeMoveApiResult> playTicTacToeMove(String sessionId, {required int to, int? from}) async {
    final data = await ApiClient.instance.put(
      '/tic-tac-toe-sessions/$sessionId/move',
      body: {'to': to, if (from != null) 'from': from},
    ) as Map<String, dynamic>;
    return TicTacToeMoveApiResult.fromJson(data);
  }

  /// Resynchronisation après reprise d'app/reconnexion — jamais mis en
  /// cache, même principe que fetchMemoryGameState.
  Future<TicTacToeSession> fetchTicTacToeState(String sessionId) async {
    final data = await ApiClient.instance.get('/tic-tac-toe-sessions/$sessionId') as Map<String, dynamic>;
    return TicTacToeSession.fromJson(data);
  }

  Future<TicTacToeSession> abandonTicTacToe(String sessionId) async {
    final data = await ApiClient.instance.put('/tic-tac-toe-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return TicTacToeSession.fromJson(data);
  }

  /// N'importe lequel des deux peut la déclencher — voir
  /// TicTacToeController::pause, seule cette personne pourra la lever.
  Future<TicTacToeSession> pauseTicTacToe(String sessionId) async {
    final data = await ApiClient.instance.put('/tic-tac-toe-sessions/$sessionId/pause') as Map<String, dynamic>;
    return TicTacToeSession.fromJson(data);
  }

  /// Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
  /// TicTacToeController::resume).
  Future<TicTacToeSession> resumeTicTacToe(String sessionId) async {
    final data = await ApiClient.instance.put('/tic-tac-toe-sessions/$sessionId/resume') as Map<String, dynamic>;
    return TicTacToeSession.fromJson(data);
  }

  Future<TicTacToeMatchStats?> cachedTicTacToeStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_tic_tac_toe_stats_$sessionId');
    if (cached == null) return null;
    return TicTacToeMatchStats.fromJson(cached);
  }

  Future<TicTacToeMatchStats> fetchTicTacToeStats(String sessionId) async {
    final cacheKey = 'cache_tic_tac_toe_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/tic-tac-toe-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return TicTacToeMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return TicTacToeMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté ou pass-and-play, voir TicTacToeTransport)
  /// — best-effort, même principe que recordMemoryGameResult.
  Future<TicTacToeSession> recordTicTacToeResult(
    String gameId, {
    required int movesCount,
    required int durationSeconds,
    String? winnerUserId,
    required bool isDraw,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/tic-tac-toe-results',
      body: {
        'moves_count': movesCount,
        'duration_seconds': durationSeconds,
        if (winnerUserId != null) 'winner_user_id': winnerUserId,
        'is_draw': isDraw,
      },
    ) as Map<String, dynamic>;
    return TicTacToeSession.fromJson(data);
  }

  // "Le Jeu des Carrés" — copie structurelle conforme des méthodes
  // "Morpion à Deux"/"Jeu de Mémoire" juste au-dessus, même convention de
  // nommage.

  Future<DotSquareSession> startDotSquares(String gameId) async {
    final data = await ApiClient.instance.post('/games/$gameId/dot-square-sessions/start') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  Future<DotSquareSession> playDotSquaresMove(String sessionId, int position) async {
    final data = await ApiClient.instance.put(
      '/dot-square-sessions/$sessionId/place',
      body: {'position': position},
    ) as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  /// Resynchronisation après reprise d'app/reconnexion — jamais mis en
  /// cache, même principe que fetchTicTacToeState.
  Future<DotSquareSession> fetchDotSquaresState(String sessionId) async {
    final data = await ApiClient.instance.get('/dot-square-sessions/$sessionId') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  /// Propose de clôturer la feuille avant qu'elle soit pleine — si le
  /// binôme avait déjà proposé, vaut confirmation et clôture (voir
  /// DotSquaresController::requestClose).
  Future<DotSquareSession> requestCloseDotSquares(String sessionId) async {
    final data = await ApiClient.instance.put('/dot-square-sessions/$sessionId/close-request') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  /// Annule sa propre proposition de clôture — réservé à qui l'a posée.
  Future<DotSquareSession> cancelCloseDotSquares(String sessionId) async {
    final data = await ApiClient.instance.put('/dot-square-sessions/$sessionId/close-cancel') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  Future<DotSquareSession> abandonDotSquares(String sessionId) async {
    final data = await ApiClient.instance.put('/dot-square-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  /// N'importe lequel des deux peut la déclencher — voir
  /// DotSquaresController::pause, seule cette personne pourra la lever.
  Future<DotSquareSession> pauseDotSquares(String sessionId) async {
    final data = await ApiClient.instance.put('/dot-square-sessions/$sessionId/pause') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  /// Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
  /// DotSquaresController::resume).
  Future<DotSquareSession> resumeDotSquares(String sessionId) async {
    final data = await ApiClient.instance.put('/dot-square-sessions/$sessionId/resume') as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  Future<DotSquareMatchStats?> cachedDotSquaresStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_dot_squares_stats_$sessionId');
    if (cached == null) return null;
    return DotSquareMatchStats.fromJson(cached);
  }

  Future<DotSquareMatchStats> fetchDotSquaresStats(String sessionId) async {
    final cacheKey = 'cache_dot_squares_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/dot-square-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return DotSquareMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return DotSquareMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté ou pass-and-play, voir DotSquaresTransport)
  /// — best-effort, même principe que recordTicTacToeResult.
  Future<DotSquareSession> recordDotSquaresResult(
    String gameId, {
    required int movesCount,
    required int durationSeconds,
    required Map<String, int> scoresByUser,
    String? winnerUserId,
    required bool isTie,
    required bool closedEarly,
    int? cols,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/dot-square-results',
      body: {
        'moves_count': movesCount,
        'duration_seconds': durationSeconds,
        'scores_by_user': scoresByUser,
        if (winnerUserId != null) 'winner_user_id': winnerUserId,
        'is_tie': isTie,
        'closed_early': closedEarly,
        if (cols != null) 'cols': cols,
      },
    ) as Map<String, dynamic>;
    return DotSquareSession.fromJson(data);
  }

  /// Historique des feuilles terminées de ce jeu pour cette Box — voir
  /// demande utilisateur : "ajouter un historique pour conserver chaque
  /// feuille avec ces statistiques". Paginé (les plus récentes d'abord,
  /// `beforeId` pour remonter plus loin) comme fetchBoxHistory.
  Future<DotSquareHistoryPage> fetchDotSquaresHistory(String gameId, {String? beforeId, int limit = 20}) async {
    final query = <String, String>{
      'limit': '$limit',
      if (beforeId != null) 'before': beforeId,
    };
    final uri = Uri(path: '/games/$gameId/dot-square-sessions', queryParameters: query);
    final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
    return DotSquareHistoryPage.fromJson(data);
  }

  // Invitations à une partie à distance (voir GameInvite) — remplace
  // l'appel direct à startXxx() côté client pour les 3 jeux ci-dessus :
  // voir GameInviteNotifier/GameInviteWaitingScreen.

  /// [friendCode] (optionnel) bascule sur une invitation HORS-BOX — défi à
  /// un ami de jeu via son code personnel plutôt qu'au binôme (voir
  /// demande utilisateur). `null` conserve le comportement existant.
  Future<GameInvite> createGameInvite(
    String gameId, {
    required String sessionType,
    Map<String, dynamic>? payload,
    String? friendCode,
    // Voir demande utilisateur : défier directement depuis "Mes amis de
    // jeu" (FriendsListScreen) — l'amitié est déjà établie, l'id suffit,
    // jamais les deux à la fois avec friendCode.
    String? friendUserId,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/invites',
      body: {
        'session_type': sessionType,
        if (payload != null) 'payload': payload,
        if (friendCode != null) 'friend_code': friendCode,
        if (friendUserId != null) 'friend_user_id': friendUserId,
      },
    ) as Map<String, dynamic>;
    return GameInvite.fromJson(data);
  }

  Future<GameInvite> fetchGameInvite(String inviteId) async {
    final data = await ApiClient.instance.get('/invites/$inviteId') as Map<String, dynamic>;
    return GameInvite.fromJson(data);
  }

  /// Invitation encore en attente pour moi, `null` s'il n'y en a aucune —
  /// voir GameInviteNotifier, poll de secours pour la pop-up d'invitation.
  Future<GameInvite?> fetchPendingInvite() async {
    final data = await ApiClient.instance.get('/invites/pending');
    if (data == null) return null;
    return GameInvite.fromJson(data as Map<String, dynamic>);
  }

  Future<GameInvite> acceptGameInvite(String inviteId) async {
    final data = await ApiClient.instance.put('/invites/$inviteId/accept') as Map<String, dynamic>;
    return GameInvite.fromJson(data);
  }

  Future<GameInvite> declineGameInvite(String inviteId) async {
    final data = await ApiClient.instance.put('/invites/$inviteId/decline') as Map<String, dynamic>;
    return GameInvite.fromJson(data);
  }

  /// Réservé à l'auteur de l'invitation — voir GameInviteWaitingScreen (bouton "Annuler").
  Future<GameInvite> cancelGameInvite(String inviteId) async {
    final data = await ApiClient.instance.put('/invites/$inviteId/cancel') as Map<String, dynamic>;
    return GameInvite.fromJson(data);
  }

  // Amis de jeu (voir demande utilisateur : défier quelqu'un hors de sa
  // propre Box) — jamais une demande d'amitié explicite, elle se crée
  // automatiquement quand une invitation hors-Box est acceptée.

  /// Mon propre code, à partager pour être défié·e.
  Future<String> fetchMyFriendCode() async {
    final data = await ApiClient.instance.get('/friends/code') as Map<String, dynamic>;
    return data['friend_code'] as String;
  }

  Future<List<PublicProfile>> fetchFriends() async {
    final data = await ApiClient.instance.get('/friends') as List;
    return data.map((e) => PublicProfile.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Bloque quelqu'un pour ses futures invitations de jeu hors-Box — sans
  /// jamais le/la prévenir (voir demande utilisateur).
  Future<void> blockUser(String blockedUserId) {
    return ApiClient.instance.post('/friends/block', body: {'blocked_user_id': blockedUserId});
  }

  /// Voir demande utilisateur : "voir la liste des personnes qu'on a
  /// bloqué et débloquer si on veut".
  Future<List<PublicProfile>> fetchBlockedUsers() async {
    final data = await ApiClient.instance.get('/friends/blocked') as List;
    return data.map((e) => PublicProfile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> unblockUser(String blockedUserId) {
    return ApiClient.instance.delete('/friends/block/$blockedUserId');
  }

  Future<PublicProfile> fetchPublicProfile(String userId) async {
    final data = await ApiClient.instance.get('/users/$userId/public-profile') as Map<String, dynamic>;
    return PublicProfile.fromJson(data);
  }

  // "Chasse aux Chiffres" — copie structurelle conforme des méthodes des 3
  // autres jeux, sauf `attempt` qui n'a pas de notion de tour.

  Future<NumberHuntSession> startNumberHunt(String gameId, {int? cellCount}) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/number-hunt-sessions/start',
      body: {if (cellCount != null) 'cell_count': cellCount},
    ) as Map<String, dynamic>;
    return NumberHuntSession.fromJson(data);
  }

  /// [wasCorrect] indique si CETTE tentative a bien marqué le point (voir
  /// NumberHuntController::attempt, arbitrage des quasi-égalités).
  Future<NumberHuntAttemptResult> attemptNumberHunt(String sessionId, int number) async {
    final data = await ApiClient.instance.put(
      '/number-hunt-sessions/$sessionId/attempt',
      body: {'number': number},
    ) as Map<String, dynamic>;
    return NumberHuntAttemptResult.fromJson(data);
  }

  Future<NumberHuntSession> fetchNumberHuntState(String sessionId) async {
    final data = await ApiClient.instance.get('/number-hunt-sessions/$sessionId') as Map<String, dynamic>;
    return NumberHuntSession.fromJson(data);
  }

  Future<NumberHuntSession> abandonNumberHunt(String sessionId) async {
    final data = await ApiClient.instance.put('/number-hunt-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return NumberHuntSession.fromJson(data);
  }

  Future<NumberHuntSession> pauseNumberHunt(String sessionId) async {
    final data = await ApiClient.instance.put('/number-hunt-sessions/$sessionId/pause') as Map<String, dynamic>;
    return NumberHuntSession.fromJson(data);
  }

  Future<NumberHuntSession> resumeNumberHunt(String sessionId) async {
    final data = await ApiClient.instance.put('/number-hunt-sessions/$sessionId/resume') as Map<String, dynamic>;
    return NumberHuntSession.fromJson(data);
  }

  Future<NumberHuntMatchStats?> cachedNumberHuntStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_number_hunt_stats_$sessionId');
    if (cached == null) return null;
    return NumberHuntMatchStats.fromJson(cached);
  }

  Future<NumberHuntMatchStats> fetchNumberHuntStats(String sessionId) async {
    final cacheKey = 'cache_number_hunt_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/number-hunt-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return NumberHuntMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return NumberHuntMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté ou pass-and-play) — best-effort, même
  /// principe que recordDotSquaresResult.
  Future<NumberHuntSession> recordNumberHuntResult(
    String gameId, {
    required int movesCount,
    required int durationSeconds,
    required Map<String, int> scoresByUser,
    String? winnerUserId,
    required bool isTie,
    int? cellCount,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/number-hunt-results',
      body: {
        'moves_count': movesCount,
        'duration_seconds': durationSeconds,
        'scores_by_user': scoresByUser,
        if (winnerUserId != null) 'winner_user_id': winnerUserId,
        'is_tie': isTie,
        if (cellCount != null) 'cell_count': cellCount,
      },
    ) as Map<String, dynamic>;
    return NumberHuntSession.fromJson(data);
  }

  // "Bataille" — copie structurelle conforme des méthodes des autres
  // jeux, sauf `flip` qui n'a pas de notion de tour ni de coup ciblé.

  Future<WarCardSession> startWarCard(String gameId) async {
    final data = await ApiClient.instance.post('/games/$gameId/war-card-sessions/start') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// "Battre" les cartes (voir demande utilisateur) — n'importe lequel des
  /// deux joueurs peut le déclencher, autant de fois qu'il veut, avant que
  /// le partage n'ait commencé.
  Future<WarCardSession> shuffleWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/shuffle') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// Partage automatique et instantané.
  Future<WarCardSession> dealAutoWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/deal-auto') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// Partage manuel — UN appel = deux cartes distribuées (voir
  /// WarCardEngine::dealManualStep côté Dart, copie de la version PHP).
  Future<WarCardSession> dealManualWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/deal-manual') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// "Commencer" — LES DEUX joueurs doivent l'appeler avant que la partie
  /// ne démarre réellement (voir WarCardEngine::readyUp).
  Future<WarCardSession> readyUpWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/ready') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// "Battre" SA PROPRE pile en cours de partie (voir demande utilisateur)
  /// — le serveur déduit de qui il s'agit via l'authentification, refuse
  /// si cette personne a déjà joué sa carte pour la manche en cours.
  Future<WarCardSession> shufflePileWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/shuffle-pile') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// [resolved] indique si les DEUX joueurs avaient déjà tapé (donc si la
  /// manche vient d'être résolue par CET appel).
  Future<WarCardFlipResult> flipWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/flip') as Map<String, dynamic>;
    return WarCardFlipResult.fromJson(data);
  }

  Future<WarCardSession> fetchWarCardState(String sessionId) async {
    final data = await ApiClient.instance.get('/war-card-sessions/$sessionId') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  /// Ramasse le pot en attente (voir demande utilisateur : "un bouton
  /// pour m'informer de ramasser... impliquer chacun proprement") — le
  /// serveur refuse (403) si ce n'est pas à CET utilisateur de ramasser.
  Future<WarCardSession> collectPotWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/collect') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  Future<WarCardSession> abandonWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  Future<WarCardSession> pauseWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/pause') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  Future<WarCardSession> resumeWarCard(String sessionId) async {
    final data = await ApiClient.instance.put('/war-card-sessions/$sessionId/resume') as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  Future<WarCardMatchStats?> cachedWarCardStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_war_card_stats_$sessionId');
    if (cached == null) return null;
    return WarCardMatchStats.fromJson(cached);
  }

  Future<WarCardMatchStats> fetchWarCardStats(String sessionId) async {
    final cacheKey = 'cache_war_card_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/war-card-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return WarCardMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return WarCardMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté ou pass-and-play) — best-effort, même
  /// principe que recordNumberHuntResult.
  Future<WarCardSession> recordWarCardResult(
    String gameId, {
    required int roundsCount,
    required int durationSeconds,
    String? winnerUserId,
    required bool isTie,
    int? deckSize,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/war-card-results',
      body: {
        'rounds_count': roundsCount,
        'duration_seconds': durationSeconds,
        if (winnerUserId != null) 'winner_user_id': winnerUserId,
        'is_tie': isTie,
        if (deckSize != null) 'deck_size': deckSize,
      },
    ) as Map<String, dynamic>;
    return WarCardSession.fromJson(data);
  }

  // "Jeu de Carte Classique" — copie structurelle conforme des méthodes de
  // "Bataille", mais tour par tour avec sous-état lead/response plutôt que
  // "les deux doivent taper" (voir SuitBattleEngine).

  Future<SuitBattleSession> startSuitBattle(String gameId, {int? deckSize}) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/suit-battle-sessions/start',
      body: {if (deckSize != null) 'deck_size': deckSize},
    ) as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// "Battre" les cartes — n'importe lequel des deux joueurs peut le
  /// déclencher, autant de fois qu'il veut, avant que le partage n'ait
  /// commencé.
  Future<SuitBattleSession> shuffleSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/shuffle') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// Partage automatique et instantané — coupe le paquet en deux éventails.
  Future<SuitBattleSession> dealAutoSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/deal-auto') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// "Commencer" — LES DEUX joueurs doivent l'appeler avant que la partie
  /// ne démarre réellement (voir SuitBattleEngine::readyUp).
  Future<SuitBattleSession> readyUpSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/ready') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// Le meneur pose [card] — devient la carte sur table, phase → réponse.
  Future<SuitBattleSession> playLeadSuitBattle(String sessionId, String card) async {
    final data = await ApiClient.instance.put(
      '/suit-battle-sessions/$sessionId/play-lead',
      body: {'card': card},
    ) as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// Le répondant joue [card] (même couleur que la carte sur table, ou un
  /// Joker) — résout l'échange immédiatement.
  Future<SuitBattleSession> respondSuitBattle(String sessionId, String card) async {
    final data = await ApiClient.instance.put(
      '/suit-battle-sessions/$sessionId/respond',
      body: {'card': card},
    ) as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// "Balayer" — fusionne l'échange révélé dans la pile de gains du
  /// vainqueur déjà déterminé, et relance une manche (voir demande
  /// utilisateur).
  Future<SuitBattleSession> sweepSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/sweep') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  /// Le répondant capture la carte sur table sans jouer — le meneur
  /// original reprend la main.
  Future<SuitBattleSession> captureLeadSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/capture-lead') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  Future<SuitBattleSession> fetchSuitBattleState(String sessionId) async {
    final data = await ApiClient.instance.get('/suit-battle-sessions/$sessionId') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  Future<SuitBattleSession> abandonSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  Future<SuitBattleSession> pauseSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/pause') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  Future<SuitBattleSession> resumeSuitBattle(String sessionId) async {
    final data = await ApiClient.instance.put('/suit-battle-sessions/$sessionId/resume') as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  Future<SuitBattleMatchStats?> cachedSuitBattleStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_suit_battle_stats_$sessionId');
    if (cached == null) return null;
    return SuitBattleMatchStats.fromJson(cached);
  }

  Future<SuitBattleMatchStats> fetchSuitBattleStats(String sessionId) async {
    final cacheKey = 'cache_suit_battle_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/suit-battle-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return SuitBattleMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return SuitBattleMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté) — best-effort, même principe que
  /// recordWarCardResult.
  Future<SuitBattleSession> recordSuitBattleResult(
    String gameId, {
    required int roundsCount,
    required int durationSeconds,
    String? winnerUserId,
    required bool isTie,
    int? deckSize,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/suit-battle-results',
      body: {
        'rounds_count': roundsCount,
        'duration_seconds': durationSeconds,
        if (winnerUserId != null) 'winner_user_id': winnerUserId,
        'is_tie': isTie,
        if (deckSize != null) 'deck_size': deckSize,
      },
    ) as Map<String, dynamic>;
    return SuitBattleSession.fromJson(data);
  }

  // "Bataille Navale" — PREMIER jeu à état partiellement caché de ce
  // projet : chaque réponse est DÉJÀ FILTRÉE côté serveur (voir
  // BattleshipEngine::toPublicArrayFor), jamais besoin de filtrer quoi
  // que ce soit côté client.

  Future<BattleshipSession> startBattleship(String gameId) async {
    final data = await ApiClient.instance.post('/games/$gameId/battleship-sessions/start') as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipSession> fetchBattleshipState(String sessionId) async {
    final data = await ApiClient.instance.get('/battleship-sessions/$sessionId') as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipSession> placeBattleshipFleet(String sessionId, List<BattleshipShip> ships) async {
    final data = await ApiClient.instance.put(
      '/battleship-sessions/$sessionId/place',
      body: {'ships': ships.map((s) => s.toJson()).toList()},
    ) as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipSession> fireBattleship(String sessionId, int cell) async {
    final data = await ApiClient.instance.put(
      '/battleship-sessions/$sessionId/fire',
      body: {'cell': cell},
    ) as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipSession> abandonBattleship(String sessionId) async {
    final data = await ApiClient.instance.put('/battleship-sessions/$sessionId/abandon') as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipSession> pauseBattleship(String sessionId) async {
    final data = await ApiClient.instance.put('/battleship-sessions/$sessionId/pause') as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipSession> resumeBattleship(String sessionId) async {
    final data = await ApiClient.instance.put('/battleship-sessions/$sessionId/resume') as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  Future<BattleshipMatchStats?> cachedBattleshipStats(String sessionId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_battleship_stats_$sessionId');
    if (cached == null) return null;
    return BattleshipMatchStats.fromJson(cached);
  }

  Future<BattleshipMatchStats> fetchBattleshipStats(String sessionId) async {
    final cacheKey = 'cache_battleship_stats_$sessionId';
    try {
      final data = await ApiClient.instance.get('/battleship-sessions/$sessionId/stats') as Map<String, dynamic>;
      await LocalCache.instance.writeJson(cacheKey, data);
      return BattleshipMatchStats.fromJson(data);
    } catch (e) {
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
      if (cached != null) return BattleshipMatchStats.fromJson(cached);
      rethrow;
    }
  }

  /// Enregistre le résultat final d'une partie jouée entièrement hors de ce
  /// service (présentiel connecté ou pass-and-play) — best-effort, même
  /// principe que recordConnectFourResult.
  Future<BattleshipSession> recordBattleshipResult(
    String gameId, {
    required int movesCount,
    required int durationSeconds,
    String? winnerUserId,
  }) async {
    final data = await ApiClient.instance.post(
      '/games/$gameId/battleship-results',
      body: {
        'moves_count': movesCount,
        'duration_seconds': durationSeconds,
        if (winnerUserId != null) 'winner_user_id': winnerUserId,
      },
    ) as Map<String, dynamic>;
    return BattleshipSession.fromJson(data);
  }

  /// Réaction en direct pendant une partie à deux téléphones (voir
  /// GameCommentSent côté back) — éphémère, jamais persistée, diffusée sur
  /// le canal de la Box déjà écouté par le jeu en cours.
  Future<void> sendGameComment(String text) {
    return ApiClient.instance.post('/game-comments', body: {'text': text});
  }

  /// STUN public + (si configuré côté back) identifiants TURN éphémères —
  /// voir VoiceCallController::iceServers. Appelé une fois au tout début
  /// d'un appel voix (voir VoiceCallService), jamais mis en cache : les
  /// identifiants TURN expirent.
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final data = await ApiClient.instance.get('/voice-calls/ice-servers') as Map<String, dynamic>;
    final servers = data['ice_servers'] as List;
    return servers.cast<Map<String, dynamic>>();
  }

  /// Un message de négociation WebRTC (voir VoiceSignal côté back) —
  /// `type` parmi voice_ready/offer/answer/ice_candidate/voice_hangup.
  Future<void> sendVoiceSignal(String type, Map<String, dynamic> payload) {
    return ApiClient.instance.post('/voice-calls/signal', body: {'type': type, 'payload': payload});
  }
}

/// Score de complicité pour "Le Sondage Surprise" — un seul pourcentage,
/// pas de classement individuel (contrairement à EmojiStoryMatchStats/quiz) :
/// ici les deux répondent à LA MÊME question, être "raccord" n'a de sens
/// qu'ensemble. Calculé CÔTÉ CLIENT à partir des cartes déjà chargées d'UNE
/// discussion précise (voir GameCardThreadScreen._threadPollStats) — chaque
/// discussion garde son propre score, jamais mélangé avec les autres
/// discussions du même jeu (demande explicite : "une discussion créée = son
/// propre score, pas ensemble").
class BlindPollStats {
  final int totalResolved;
  final int aligned;
  final double percentage;

  const BlindPollStats({required this.totalResolved, required this.aligned, required this.percentage});
}

/// Réponse brute de PUT .../answer — pas besoin du modèle GameCardSend
/// complet ici, juste de confirmer que l'appel a réussi.
class GameCardSendUpdate {
  final String id;
  final String answer;

  const GameCardSendUpdate({required this.id, required this.answer});

  factory GameCardSendUpdate.fromJson(Map<String, dynamic> json) => GameCardSendUpdate(
        id: json['id'] as String,
        answer: json['answer'] as String,
      );
}
