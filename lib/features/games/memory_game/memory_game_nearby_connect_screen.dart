import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../nearby/nearby_identity.dart';
import '../nearby/nearby_permissions.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../models/public_profile.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import 'memory_game_board_screen.dart';
import 'memory_game_difficulty_screen.dart';
import 'memory_game_transport_nearby.dart';

const _kNearbyServiceId = 'app.binome.memory_game';

/// Mode "présentiel connecté" : établit la connexion Bluetooth/WiFi Direct
/// (voir NearbyMemoryGameTransport) puis, une fois connecté, l'hôte choisit
/// la difficulté (l'invité attend simplement — le plateau lui arrive dans
/// le message `init`).
///
/// [targetFriend] : non-null pour un défi à UN AMI PRÉCIS (voir demande utilisateur), au lieu du
/// binôme habituel — dans les deux cas, seule une connexion dont l'identité annoncée correspond
/// exactement à la personne recherchée est acceptée (voir NearbyIdentity), jamais le premier appareil
/// trouvé : sans ça, un binôme ET un ami tous deux à portée en même temps pouvaient se mélanger.
class MemoryGameNearbyConnectScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final PublicProfile? targetFriend;

  const MemoryGameNearbyConnectScreen({super.key, required this.game, required this.user, this.targetFriend});

  @override
  State<MemoryGameNearbyConnectScreen> createState() => _MemoryGameNearbyConnectScreenState();
}

enum _ConnectStep { choose, hosting, discovering, connected, choosingDifficulty }

class _MemoryGameNearbyConnectScreenState extends State<MemoryGameNearbyConnectScreen> {
  final _nearby = Nearby();
  _ConnectStep _step = _ConnectStep.choose;
  String? _error;
  String? _connectedEndpointId;
  bool _isHost = false;
  // Message à afficher si les permissions/la localisation bloquent (voir NearbyPermissions).
  String _permissionProblemKey = 'memory_nearby_permission_denied';

  Future<bool> _ensurePermissions() async {
    // Seules les permissions qui existent sur CE téléphone sont demandées (voir NearbyPermissions).
    final problem = await NearbyPermissions.problemKey();
    _permissionProblemKey = problem ?? _permissionProblemKey;
    return problem == null;
  }

  /// Identifiant de la SEULE personne avec qui cette recherche doit aboutir — le binôme (résolu via
  /// BoxScope, comme avant) ou l'ami précis choisi avant d'ouvrir cet écran (voir [widget.targetFriend]
  /// et demande utilisateur : "aussi si je veux jouer avec mon binôme les amis autour sont ignorés").
  /// `null` seulement si le mode binôme est demandé sans binôme connu (Box sans partenaire) — l'écran
  /// affiche alors l'erreur générique existante plutôt que de chercher n'importe qui.
  String? _expectedUserId() {
    final friend = widget.targetFriend;
    if (friend != null) return friend.id;
    final box = BoxScope.of(context).currentBox;
    return box?.partnerOf(widget.user.id)?.id;
  }

  Future<void> _startHosting() async {
    if (!await _ensurePermissions()) {
      if (mounted) setState(() => _error = LocaleScope.t(context, _permissionProblemKey));
      return;
    }
    if (_expectedUserId() == null) {
      if (mounted) setState(() => _error = LocaleScope.t(context, 'memory_nearby_start_host_error'));
      return;
    }
    setState(() {
      _step = _ConnectStep.hosting;
      _error = null;
      _isHost = true;
    });

    try {
      await _nearby.startAdvertising(
        NearbyIdentity.encode(widget.user.id, widget.user.prenom),
        Strategy.P2P_POINT_TO_POINT,
        serviceId: _kNearbyServiceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (_) {
      if (mounted) {
        setState(() { _error = LocaleScope.t(context, 'memory_nearby_start_host_error'); _step = _ConnectStep.choose; });
      }
    }
  }

  Future<void> _startDiscovering() async {
    if (!await _ensurePermissions()) {
      if (mounted) setState(() => _error = LocaleScope.t(context, _permissionProblemKey));
      return;
    }
    final expectedUserId = _expectedUserId();
    if (expectedUserId == null) {
      if (mounted) setState(() => _error = LocaleScope.t(context, 'memory_nearby_start_discover_error'));
      return;
    }
    setState(() {
      _step = _ConnectStep.discovering;
      _error = null;
      _isHost = false;
    });

    try {
      await _nearby.startDiscovery(
        NearbyIdentity.encode(widget.user.id, widget.user.prenom),
        Strategy.P2P_POINT_TO_POINT,
        serviceId: _kNearbyServiceId,
        onEndpointFound: (endpointId, endpointName, serviceId) {
          // Ignoré si ce n'est pas la personne recherchée — voir doc de classe. Un appareil trop
          // ancien (avant cette vérification, qui ne diffuse encore que son prénom) est traité comme
          // non identifiable, donc jamais accepté non plus.
          final identity = NearbyIdentity.decode(endpointName);
          if (identity == null || identity.userId != expectedUserId) return;
          _nearby.requestConnection(
            NearbyIdentity.encode(widget.user.id, widget.user.prenom),
            endpointId,
            onConnectionInitiated: _onConnectionInitiated,
            onConnectionResult: _onConnectionResult,
            onDisconnected: _onDisconnected,
          );
        },
        onEndpointLost: (_) {},
      );
    } catch (_) {
      if (mounted) {
        setState(() { _error = LocaleScope.t(context, 'memory_nearby_start_discover_error'); _step = _ConnectStep.choose; });
      }
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    // Voir doc de classe : n'accepte QUE si l'identité annoncée par l'appareil qui se connecte
    // correspond exactement à la personne recherchée — sinon on la refuse explicitement (voir
    // Nearby.rejectConnection) et on continue d'attendre/chercher la bonne personne.
    final identity = NearbyIdentity.decode(info.endpointName);
    final expectedUserId = _expectedUserId();
    if (identity == null || expectedUserId == null || identity.userId != expectedUserId) {
      unawaited(_nearby.rejectConnection(endpointId));
      return;
    }
    _comms = NearbyComms(nearby: _nearby, endpointId: endpointId);
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (fromEndpointId, payload) {
        // Le canal de chat (voir NearbyComms) consomme d'abord ses propres
        // messages ('text_message') — tout le reste continue vers le
        // transport du jeu inchangé.
        if (_comms?.handleIncoming(payload) == true) return;
        _transport?.onPayloadReceived(fromEndpointId, payload);
      },
    );
  }

  NearbyMemoryGameTransport? _transport;
  NearbyComms? _comms;

  void _onConnectionResult(String endpointId, Status status) {
    if (!mounted) return;
    if (status == Status.CONNECTED) {
      if (_isHost) {
        _nearby.stopAdvertising();
      } else {
        _nearby.stopDiscovery();
      }
      setState(() {
        _connectedEndpointId = endpointId;
        _step = _isHost ? _ConnectStep.choosingDifficulty : _ConnectStep.connected;
      });

      if (!_isHost) {
        // L'invité attend le plateau : construit tout de suite un
        // transport en écoute, poussé dès la réception du message `init`.
        final transport = NearbyMemoryGameTransport.guest(nearby: _nearby, endpointId: endpointId);
        _transport = transport;
        transport.stateStream.first.then((_) {
          if (mounted) _openBoard(transport);
        });
      }
    } else {
      setState(() {
        _error = LocaleScope.t(context, 'memory_nearby_connection_failed');
        _step = _ConnectStep.choose;
      });
    }
  }

  void _onDisconnected(String endpointId) {
    if (!mounted) return;
    if (_step != _ConnectStep.connected) return;
    setState(() {
      _error = LocaleScope.t(context, 'memory_nearby_disconnected');
      _step = _ConnectStep.choose;
      _connectedEndpointId = null;
    });
  }

  void _startHostGame(int pairCount) {
    final endpointId = _connectedEndpointId;
    if (endpointId == null) return;
    final transport = NearbyMemoryGameTransport.host(nearby: _nearby, endpointId: endpointId, pairCount: pairCount);
    _transport = transport;
    _openBoard(transport);
  }

  void _openBoard(NearbyMemoryGameTransport transport) {
    final friend = widget.targetFriend;
    // Voir demande utilisateur : "rendre l'option bluetooth gratuite partout comme l'option un
    // telephone" — que ce soit avec le binôme ou avec un ami, plus aucun suivi/déclaration de forfait
    // journalier (voir NearbyBillingTracker/FriendChallengeNearbyBillingTracker, plus jamais appelés).
    final partnerName = friend?.prenom ?? BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.prenom;
    final partnerAvatar = friend?.avatar ?? BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.avatar;
    final myRole = _isHost ? kNearbyHostRole : kNearbyGuestRole;
    final partnerRole = _isHost ? kNearbyGuestRole : kNearbyHostRole;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MemoryGameBoardScreen(
          game: widget.game,
          user: widget.user,
          transport: transport,
          playerNames: {myRole: widget.user.prenom, partnerRole: partnerName ?? LocaleScope.t(context, 'memory_score_player_fallback')},
          playerAvatars: {myRole: widget.user.avatar, partnerRole: partnerAvatar},
          nearbyComms: _comms,
          nearbyMyName: widget.user.prenom,
          nearbyPartnerName: partnerName ?? LocaleScope.t(context, 'memory_score_player_fallback'),
        ),
      ),
    );

    // Résultat enregistré côté serveur UNIQUEMENT pour le binôme (voir MemoryGameController::
    // recordResult, qui exige une Box avec partenaire) — un défi d'ami en Bluetooth n'a pas encore ce
    // mécanisme côté serveur ; la partie se joue normalement, seules les statistiques ne sont pas
    // encore conservées pour ce cas précis.
    if (_isHost && friend == null) {
      final partnerId = BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.id;
      unawaited(_postResultWhenFinished(transport, partnerId));
    }
  }

  Future<void> _postResultWhenFinished(NearbyMemoryGameTransport transport, String? partnerUserId) async {
    if (partnerUserId == null) return;
    await for (final state in transport.stateStream) {
      if (state.finished) {
        final pairs = transport.pairsByUserId(hostUserId: widget.user.id, guestUserId: partnerUserId);
        final duration = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds : 0;
        try {
          await GameService.instance.recordMemoryGameResult(
            widget.game.id,
            pairCount: state.board.length ~/ 2,
            movesCount: state.movesCount,
            durationSeconds: duration,
            pairsByUser: pairs,
          );
        } catch (_) {
          // Best-effort : aucun mécanisme de retry hors-ligne ailleurs dans
          // l'app à réutiliser ici (voir le plan).
        }
        break;
      }
    }
  }

  @override
  void dispose() {
    // Ne ferme PAS _comms ici : l'écran de plateau (MemoryGameBoardScreen)
    // en a besoin après le remplacement de route (pushReplacement) — c'est
    // lui qui possède le cycle de vie du canal de chat désormais.
    _nearby.stopAdvertising();
    _nearby.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(LocaleScope.t(context, 'memory_mode_nearby_title')),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: switch (_step) {
            _ConnectStep.choosingDifficulty => MemoryGameDifficultyList(theme: theme, onSelected: _startHostGame),
            _ => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(_error!, style: GoogleFonts.nunito(fontSize: 13, color: Colors.redAccent)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_step == _ConnectStep.choose) ...[
                      Text(
                        LocaleScope.t(context, 'memory_nearby_intro_title'),
                        style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        LocaleScope.t(context, 'memory_nearby_intro_subtitle'),
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _startHosting,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: Text(LocaleScope.t(context, 'memory_nearby_create')),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _startDiscovering,
                        icon: const Icon(Icons.search_rounded),
                        label: Text(LocaleScope.t(context, 'memory_nearby_join')),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ] else if (_step == _ConnectStep.hosting || _step == _ConnectStep.discovering) ...[
                      const SizedBox(height: 40),
                      Center(child: CircularProgressIndicator(color: theme.primary)),
                      const SizedBox(height: 16),
                      Text(
                        _step == _ConnectStep.hosting
                            ? LocaleScope.t(context, 'memory_nearby_waiting_host')
                            : LocaleScope.t(context, 'memory_nearby_searching'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                    ] else if (_step == _ConnectStep.connected) ...[
                      const SizedBox(height: 40),
                      Center(child: CircularProgressIndicator(color: theme.primary)),
                      const SizedBox(height: 16),
                      Text(
                        LocaleScope.t(context, 'memory_nearby_connected_waiting'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                    ],
                  ],
                ),
              ),
          },
        ),
      ),
    );
  }
}
