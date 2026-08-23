import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/emoji_story_session.dart';
import '../../models/emoji_story_stats.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../models/game_card_send.dart';
import '../../models/memory_game_session.dart';
import '../../models/memory_game_stats.dart';
import '../../models/replies_page.dart';
import '../../models/send.dart';

class GameService {
  GameService._();
  static final GameService instance = GameService._();

  Future<List<Game>> fetchGames() async {
    final data = await ApiClient.instance.get('/games') as List;
    return data.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
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
