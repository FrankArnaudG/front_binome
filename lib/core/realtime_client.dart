import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';
import 'token_storage.dart';

class RealtimeEvent {
  final String channel;
  final String event;
  final Map<String, dynamic>? data;
  RealtimeEvent({required this.channel, required this.event, this.data});
}

/// Connexion websocket vers Laravel Reverb. Implémente directement le
/// sous-ensemble du protocole Pusher dont on a besoin (connexion, canal
/// presence authentifié, écoute d'événements) plutôt que de dépendre d'un
/// plugin natif — voir la note dans le plan pour le paquet écarté.
///
/// N'est jamais la seule source de vérité : chaque écran qui l'utilise doit
/// garder un polling de secours en parallèle (voir BoxWaitingScreen) — si le
/// socket échoue silencieusement (pas de reconnexion automatique ici), l'app
/// reste quand même cohérente à terme.
///
/// Plusieurs écrans peuvent s'abonner au même canal Box en même temps (ex.
/// DashboardTab reste monté dans l'IndexedStack pendant qu'un
/// SlideDetailScreen s'ouvre par-dessus) — chaque canal garde donc un
/// ENSEMBLE d'écouteurs plutôt qu'un seul, avec un compte de référence côté
/// abonnement serveur : le `pusher:unsubscribe` réel n'est envoyé que quand
/// le dernier écouteur local se désabonne.
class RealtimeClient {
  RealtimeClient._();
  static final RealtimeClient instance = RealtimeClient._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _socketId;
  final _subscribedChannels = <String>{};
  final _eventCallbacks = <String, Set<void Function(RealtimeEvent event)>>{};
  final _presenceCallbacks = <String, Set<void Function(Set<String> memberIds)>>{};
  final _presentMembers = <String, Set<String>>{};
  Timer? _reconnectTimer;

  // Chien de garde : Reverb envoie un `pusher:ping` toutes les ~30-60s (voir
  // config par défaut), donc silence total pendant plus de 45s = connexion
  // morte à coup sûr — sans ça, une coupure SILENCIEUSE (écran verrouillé,
  // bascule WiFi/4G, NAT d'opérateur qui tue les connexions inactives) ne
  // déclenche jamais [onDone]/[onError] : `_channel` reste non-null pour
  // toujours, [connect] refuse alors de rouvrir quoi que ce soit, et plus
  // aucun événement temps réel n'arrive (invitations de jeu comprises)
  // jusqu'à ce que le PROCESSUS de l'app soit tué et relancé (voir demande
  // utilisateur : "sauf si je sors carrément des deux app et reviens").
  DateTime? _lastMessageAt;
  Timer? _watchdogTimer;
  static const _watchdogSilenceLimit = Duration(seconds: 45);

  bool get isConnected => _channel != null;

  /// Ne lève jamais : une indisponibilité de Reverb (serveur arrêté, tunnel
  /// adb reverse pas encore rétabli, etc.) ne doit jamais faire planter
  /// l'app — juste dégrader silencieusement le temps réel, l'écran
  /// appelant garde son polling de secours.
  Future<void> connect() async {
    if (_channel != null) return;

    final scheme = ApiConfig.reverbUseTLS ? 'wss' : 'ws';
    final uri = Uri(
      scheme: scheme,
      host: ApiConfig.reverbHost,
      port: ApiConfig.reverbPort,
      path: '/app/${ApiConfig.reverbAppKey}',
      queryParameters: {'protocol': '7', 'client': 'binome-flutter', 'version': '1.0'},
    );

    final channel = WebSocketChannel.connect(uri);

    try {
      await channel.ready;
    } catch (e) {
      // _channel reste null : un prochain appel à connect() retentera,
      // plutôt que de rester bloqué à croire qu'on est déjà connecté.
      debugPrint('Reverb: échec de connexion ($e)');
      _scheduleReconnect();
      return;
    }

    _channel = channel;
    _reconnectTimer?.cancel();
    _lastMessageAt = DateTime.now();
    _startWatchdog();
    _subscription = channel.stream.listen(
      _handleMessage,
      onError: (e) => debugPrint('Reverb websocket error: $e'),
      // Coupure INATTENDUE (serveur redémarré, réseau perdu...) — jamais
      // pour un [disconnect] volontaire, qui vide ses propres abonnements
      // avant d'appeler _reset() et ne repasse donc jamais par ici avec
      // des écouteurs encore enregistrés (voir _scheduleReconnect).
      onDone: () {
        _reset();
        _scheduleReconnect();
      },
    );
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final lastMessageAt = _lastMessageAt;
      if (_channel == null || lastMessageAt == null) return;
      if (DateTime.now().difference(lastMessageAt) >= _watchdogSilenceLimit) {
        debugPrint('Reverb: silence > ${_watchdogSilenceLimit.inSeconds}s, connexion présumée morte — reconnexion forcée');
        // Ferme nous-mêmes ce qui reste d'un socket à moitié mort, PUIS
        // force [_reset]/[_scheduleReconnect] directement plutôt que de
        // compter sur [onDone] : sur une connexion réellement morte (TCP à
        // moitié ouvert), la fermeture peut ne jamais aboutir proprement —
        // sans appel direct ici, `_channel` resterait non-null
        // indéfiniment et ce tick se répéterait pour rien toutes les 10s.
        _channel?.sink.close();
        _reset();
        _scheduleReconnect();
        return;
      }

      // Filet de sécurité INDÉPENDANT du silence ci-dessus : la connexion
      // elle-même peut rester parfaitement vivante (pings réguliers, voir
      // _lastMessageAt) alors qu'UN abonnement précis a échoué à se
      // rétablir après une reconnexion passée — voir [_resubscribeAll],
      // dont l'appel à [_authorize] peut échouer une fois (backend
      // momentanément indisponible pile à ce moment-là) et abandonner ce
      // canal SANS RETENTER ENSUITE, silencieusement, jusqu'au prochain
      // cycle de reconnexion complet (voir demande utilisateur : "après un
      // jeu... ça se connecte pas" persistant malgré le chien de garde
      // ci-dessus — la connexion elle-même n'était probablement jamais
      // morte, juste CE canal). Rejoué ici à chaque tick : sans effet
      // (juste un `continue` immédiat) pour un canal déjà bien abonné.
      unawaited(_resubscribeAll());
    });
  }

  /// Retente [connect] après une courte pause, PUIS rejoue tous les
  /// abonnements dont un écran/singleton a encore besoin (voir
  /// [_resubscribeAll]) — sans ça, une coupure momentanée de Reverb (ex.
  /// redémarrage du serveur en cours de test) laissait l'app définitivement
  /// sourde au temps réel jusqu'au prochain relancement complet : rien ne
  /// redemandait jamais la connexion (voir demande utilisateur : "toujours
  /// rien" après un redémarrage de Reverb, alors que le serveur allait très
  /// bien). `_eventCallbacks`/`_presenceCallbacks` ne sont volontairement
  /// PAS effacés par [_reset] : ce sont ces mêmes abonnements qu'on rejoue
  /// ici, aucun appelant n'a besoin de se réabonner lui-même.
  void _scheduleReconnect() {
    if (_eventCallbacks.isEmpty && _presenceCallbacks.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      await connect();
      if (_channel != null) await _resubscribeAll();
    });
  }

  /// Renvoie `pusher:subscribe` pour chaque canal qui avait encore au moins
  /// un écouteur au moment de la coupure — voir [_scheduleReconnect].
  Future<void> _resubscribeAll() async {
    for (var i = 0; i < 20 && _socketId == null; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_socketId == null) return;

    final channelNames = {..._eventCallbacks.keys, ..._presenceCallbacks.keys};
    for (final channelName in channelNames) {
      if (_subscribedChannels.contains(channelName)) continue;

      if (channelName.startsWith('presence-') || channelName.startsWith('private-')) {
        final auth = await _authorize(channelName, _socketId!);
        if (auth == null) continue;
        _subscribedChannels.add(channelName);
        _send({
          'event': 'pusher:subscribe',
          'data': {'channel': channelName, 'auth': auth['auth'], 'channel_data': auth['channel_data']},
        });
      } else {
        _subscribedChannels.add(channelName);
        _send({'event': 'pusher:subscribe', 'data': {'channel': channelName}});
      }
    }
  }

  void _handleMessage(dynamic raw) {
    _lastMessageAt = DateTime.now();
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    final event = message['event'] as String?;
    final channel = message['channel'] as String?;
    final rawData = message['data'];
    final data = rawData is String ? jsonDecode(rawData) as Map<String, dynamic>? : rawData as Map<String, dynamic>?;

    if (event == 'pusher:connection_established') {
      _socketId = data?['socket_id'] as String?;
      return;
    }

    if (event == 'pusher:ping') {
      _send({'event': 'pusher:pong', 'data': {}});
      return;
    }

    if (event == null || channel == null) return;

    if (event == 'pusher_internal:subscription_succeeded') {
      // Payload de départ d'un canal presence : liste des membres déjà
      // présents (`presence.ids`) — donne "partenaire en ligne" sans
      // attendre un member_added.
      final ids = (data?['presence'] as Map<String, dynamic>?)?['ids'] as List?;
      if (ids != null) {
        final members = ids.map((e) => e.toString()).toSet();
        _presentMembers[channel] = members;
        for (final cb in _presenceCallbacks[channel]?.toList() ?? const []) {
          cb(members);
        }
      }
      return;
    }

    if (event == 'pusher_internal:member_added') {
      final userId = data?['user_id']?.toString();
      if (userId != null) {
        final members = _presentMembers.putIfAbsent(channel, () => <String>{});
        members.add(userId);
        for (final cb in _presenceCallbacks[channel]?.toList() ?? const []) {
          cb(members);
        }
      }
      return;
    }

    if (event == 'pusher_internal:member_removed') {
      final userId = data?['user_id']?.toString();
      if (userId != null) {
        final members = _presentMembers.putIfAbsent(channel, () => <String>{});
        members.remove(userId);
        for (final cb in _presenceCallbacks[channel]?.toList() ?? const []) {
          cb(members);
        }
      }
      return;
    }

    final realtimeEvent = RealtimeEvent(channel: channel, event: event, data: data);
    for (final cb in _eventCallbacks[channel]?.toList() ?? const []) {
      cb(realtimeEvent);
    }
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void _reset() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    _socketId = null;
    _subscribedChannels.clear();
    _presentMembers.clear();
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _lastMessageAt = null;
  }

  /// Signe l'accès au canal presence via notre backend (`/broadcasting/auth`,
  /// protégé par le même Bearer token que le reste de l'API) puis
  /// s'abonne. [onEvent] reçoit tous les événements applicatifs du canal
  /// (BoxPaired, BoxDissolved, SendCreated...). [onPresenceChange], si fourni,
  /// reçoit l'ensemble des ids utilisateur actuellement présents sur le
  /// canal à chaque changement (abonnement initial, arrivée, départ) — et,
  /// s'il rejoint un canal déjà abonné, l'état déjà connu immédiatement.
  Future<void> subscribeToBox(
    String boxId, {
    required void Function(RealtimeEvent event) onEvent,
    void Function(Set<String> memberIds)? onPresenceChange,
  }) async {
    await connect();

    final channelName = 'presence-box.$boxId';
    _eventCallbacks.putIfAbsent(channelName, () => {}).add(onEvent);
    if (onPresenceChange != null) {
      _presenceCallbacks.putIfAbsent(channelName, () => {}).add(onPresenceChange);
      final existing = _presentMembers[channelName];
      if (existing != null) onPresenceChange(existing);
    }

    // Déjà abonné·e côté serveur (un autre écran écoute déjà ce canal) —
    // l'écouteur local ci-dessus suffit, pas besoin de re-souscrire.
    if (_subscribedChannels.contains(channelName)) return;

    // La connexion peut ne pas avoir encore reçu son socket_id au premier
    // appel juste après connect() ; on attend un court instant plutôt que
    // d'échouer l'abonnement.
    for (var i = 0; i < 20 && _socketId == null; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_socketId == null) {
      debugPrint('Reverb: pas de socket_id, abandon de l\'abonnement à $channelName');
      return;
    }

    final auth = await _authorize(channelName, _socketId!);
    if (auth == null) return;

    _subscribedChannels.add(channelName);

    _send({
      'event': 'pusher:subscribe',
      'data': {
        'channel': channelName,
        'auth': auth['auth'],
        'channel_data': auth['channel_data'],
      },
    });
  }

  /// S'abonne à un canal PRIVÉ authentifié (même handshake `/broadcasting/auth`
  /// que [subscribeToBox], mais sans notion de présence/membres — voir
  /// routes/channels.php côté backend, `Broadcast::channel` sans
  /// `PresenceChannel`) : pour tout ce qui n'est pas scopé à une Box, par
  /// exemple le canal personnel `App.Models.User.{id}` (défis d'amis de
  /// jeu hors de sa propre Box, voir demande utilisateur) ou une session de
  /// jeu hors-Box dédiée (`memory-game-session.{id}`). [channelName] est le
  /// nom BRUT tel qu'enregistré côté backend, SANS le préfixe `private-`
  /// (ajouté ici, comme [subscribeToBox] ajoute `presence-` lui-même).
  Future<void> subscribePrivate(String channelName, {required void Function(RealtimeEvent event) onEvent}) async {
    await connect();

    final fullChannelName = 'private-$channelName';
    _eventCallbacks.putIfAbsent(fullChannelName, () => {}).add(onEvent);

    if (_subscribedChannels.contains(fullChannelName)) return;

    for (var i = 0; i < 20 && _socketId == null; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_socketId == null) {
      debugPrint('Reverb: pas de socket_id, abandon de l\'abonnement à $fullChannelName');
      return;
    }

    final auth = await _authorize(fullChannelName, _socketId!);
    if (auth == null) return;

    _subscribedChannels.add(fullChannelName);
    _send({
      'event': 'pusher:subscribe',
      'data': {'channel': fullChannelName, 'auth': auth['auth']},
    });
  }

  /// Retire UNIQUEMENT l'écouteur passé ici — voir [unsubscribeFromBox],
  /// même principe pour un canal privé abonné via [subscribePrivate].
  void unsubscribePrivate(String channelName, {required void Function(RealtimeEvent event) onEvent}) {
    final fullChannelName = 'private-$channelName';
    _eventCallbacks[fullChannelName]?.remove(onEvent);
    if (_eventCallbacks[fullChannelName]?.isNotEmpty ?? false) return;

    if (!_subscribedChannels.remove(fullChannelName)) return;
    _eventCallbacks.remove(fullChannelName);
    _send({
      'event': 'pusher:unsubscribe',
      'data': {'channel': fullChannelName},
    });
  }

  /// S'abonne à un canal PUBLIC (pas de préfixe `presence-`/`private-`, donc
  /// pas de handshake `/broadcasting/auth` — contrairement à
  /// [subscribeToBox]) : pour un signal qui ne porte aucune donnée propre à
  /// un couple, diffusé à toute l'app (voir GameCatalogUpdated, "le
  /// catalogue de jeux a changé côté admin, recharge-le"). Même logique de
  /// comptage d'écouteurs que [subscribeToBox] : plusieurs écrans peuvent
  /// s'abonner au même canal, l'abonnement serveur réel n'est fait qu'une
  /// fois.
  Future<void> subscribePublic(String channelName, {required void Function(RealtimeEvent event) onEvent}) async {
    await connect();

    _eventCallbacks.putIfAbsent(channelName, () => {}).add(onEvent);

    if (_subscribedChannels.contains(channelName)) return;

    _subscribedChannels.add(channelName);
    _send({
      'event': 'pusher:subscribe',
      'data': {'channel': channelName},
    });
  }

  /// Retire UNIQUEMENT l'écouteur passé ici — voir [unsubscribeFromBox], même
  /// principe pour un canal public abonné via [subscribePublic].
  void unsubscribePublic(String channelName, {required void Function(RealtimeEvent event) onEvent}) {
    _eventCallbacks[channelName]?.remove(onEvent);
    if (_eventCallbacks[channelName]?.isNotEmpty ?? false) return;

    if (!_subscribedChannels.remove(channelName)) return;
    _eventCallbacks.remove(channelName);
    _send({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channelName},
    });
  }

  Future<Map<String, dynamic>?> _authorize(String channelName, String socketId) async {
    final token = await TokenStorage.instance.readToken();

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.broadcastAuthUrl),
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: {'socket_id': socketId, 'channel_name': channelName},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Reverb: échec autorisation $channelName: $e');
      return null;
    }
  }

  /// Retire UNIQUEMENT les écouteurs passés ici — le canal reste abonné côté
  /// serveur tant qu'il reste au moins un écouteur (événement ou présence)
  /// enregistré par un autre écran.
  void unsubscribeFromBox(
    String boxId, {
    void Function(RealtimeEvent event)? onEvent,
    void Function(Set<String> memberIds)? onPresenceChange,
  }) {
    final channelName = 'presence-box.$boxId';
    if (onEvent != null) _eventCallbacks[channelName]?.remove(onEvent);
    if (onPresenceChange != null) _presenceCallbacks[channelName]?.remove(onPresenceChange);

    final stillListening = (_eventCallbacks[channelName]?.isNotEmpty ?? false) ||
        (_presenceCallbacks[channelName]?.isNotEmpty ?? false);
    if (stillListening) {
      // Un autre écouteur en a encore besoin (typiquement
      // GameInviteNotifier, abonné en permanence pour les invitations) —
      // on ne coupe pas l'abonnement partagé, mais on force un nouveau
      // `pusher:subscribe` dessus plutôt que de le laisser tel quel. Sans
      // ça, une partie qui se termine (abandon ou fin normale) ne
      // garantissait jamais que ce canal partagé était réellement à jour
      // côté serveur — un abonnement resté silencieusement caduc restait
      // caduc jusqu'à ce que l'app entière soit relancée (voir demande
      // utilisateur : "si je quitte le jeu... le binôme ne reçoit plus de
      // notification... sauf si je ferme les deux app"). Idempotent et sans
      // risque : Reverb accepte un nouveau pusher:subscribe sur un canal
      // déjà abonné.
      _subscribedChannels.remove(channelName);
      unawaited(_resubscribeAll());
      return;
    }

    if (!_subscribedChannels.remove(channelName)) return;
    _eventCallbacks.remove(channelName);
    _presenceCallbacks.remove(channelName);
    _presentMembers.remove(channelName);
    _send({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channelName},
    });
  }

  /// Coupure VOLONTAIRE (ex. déconnexion du compte) — contrairement à une
  /// coupure subie, vide aussi les abonnements eux-mêmes : rien ne doit
  /// tenter de se reconnecter/se réabonner ensuite (voir
  /// [_scheduleReconnect], qui ne fait justement rien si ces deux maps
  /// sont vides).
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _eventCallbacks.clear();
    _presenceCallbacks.clear();
    await _channel?.sink.close();
    _reset();
  }
}
