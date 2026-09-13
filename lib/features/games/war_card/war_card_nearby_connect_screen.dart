import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_service.dart';
import '../nearby_billing_tracker.dart';
import 'war_card_board_screen.dart';
import 'war_card_difficulty_screen.dart';
import 'war_card_transport_nearby.dart';

const _kNearbyServiceId = 'app.binome.war_card';

/// Mode "présentiel connecté" : établit la connexion Bluetooth/WiFi Direct
/// (voir NearbyWarCardTransport) puis, une fois connecté, l'hôte choisit
/// la taille du paquet (l'invité attend simplement — le palier lui
/// arrive dans le message `init`) — copie structurelle conforme de
/// dot_squares_nearby_connect_screen.dart.
class WarCardNearbyConnectScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const WarCardNearbyConnectScreen({super.key, required this.game, required this.user});

  @override
  State<WarCardNearbyConnectScreen> createState() => _WarCardNearbyConnectScreenState();
}

enum _ConnectStep { choose, hosting, discovering, connected, choosingDifficulty }

class _WarCardNearbyConnectScreenState extends State<WarCardNearbyConnectScreen> {
  final _nearby = Nearby();
  _ConnectStep _step = _ConnectStep.choose;
  String? _error;
  String? _connectedEndpointId;
  bool _isHost = false;
  NearbyWarCardTransport? _transport;

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> _startHosting() async {
    if (!await _ensurePermissions()) {
      if (mounted) setState(() => _error = LocaleScope.t(context, 'memory_nearby_permission_denied'));
      return;
    }
    setState(() {
      _step = _ConnectStep.hosting;
      _error = null;
      _isHost = true;
    });

    try {
      await _nearby.startAdvertising(
        widget.user.prenom,
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
      if (mounted) setState(() => _error = LocaleScope.t(context, 'memory_nearby_permission_denied'));
      return;
    }
    setState(() {
      _step = _ConnectStep.discovering;
      _error = null;
      _isHost = false;
    });

    try {
      await _nearby.startDiscovery(
        widget.user.prenom,
        Strategy.P2P_POINT_TO_POINT,
        serviceId: _kNearbyServiceId,
        onEndpointFound: (endpointId, endpointName, serviceId) {
          _nearby.requestConnection(
            widget.user.prenom,
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
    // Confiance de couple : acceptation automatique, pas de code PIN à
    // saisir (même principe que les autres jeux).
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (fromEndpointId, payload) {
        _transport?.onPayloadReceived(fromEndpointId, payload);
      },
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (!mounted) return;
    if (status == Status.CONNECTED) {
      if (_isHost) {
        _nearby.stopAdvertising();
      } else {
        _nearby.stopDiscovery();
      }
      if (_isHost) {
        setState(() {
          _connectedEndpointId = endpointId;
          _step = _ConnectStep.choosingDifficulty;
        });
      } else {
        setState(() => _step = _ConnectStep.connected);
        // L'invité attend le nombre de cartes : construit tout de suite
        // un transport en écoute, poussé dès la réception du message
        // `init`.
        final transport = NearbyWarCardTransport.guest(nearby: _nearby, endpointId: endpointId);
        _transport = transport;
        transport.stateStream.first.then((state) {
          if (mounted) _openBoard(transport, state.deck.length);
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
    });
  }

  void _startHostGame(int deckSize) {
    final endpointId = _connectedEndpointId;
    if (endpointId == null) return;
    final transport = NearbyWarCardTransport.host(nearby: _nearby, endpointId: endpointId, deckSize: deckSize);
    _transport = transport;
    _openBoard(transport, deckSize);
  }

  void _openBoard(NearbyWarCardTransport transport, int deckSize) {
    final box = BoxScope.of(context).currentBox;
    // Facturation forfaitaire du mode Nearby (voir NearbyBillingTracker/
    // demande utilisateur) — uniquement dans une vraie Box (jamais pour un
    // défi entre amis hors couple, sans portefeuille partagé).
    if (box != null) NearbyBillingTracker.instance.markPlayedToday(box.id);
    final partner = box?.partnerOf(widget.user.id);
    final myRole = _isHost ? kWarCardHostRole : kWarCardGuestRole;
    final partnerRole = _isHost ? kWarCardGuestRole : kWarCardHostRole;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WarCardBoardScreen(
          game: widget.game,
          user: widget.user,
          transport: transport,
          playerNames: {myRole: widget.user.prenom, partnerRole: partner?.prenom ?? LocaleScope.t(context, 'memory_score_player_fallback')},
          playerAvatars: {myRole: widget.user.avatar, partnerRole: partner?.avatar},
        ),
      ),
    );

    if (_isHost) {
      unawaited(_postResultWhenFinished(transport, partner?.id, deckSize));
    }
  }

  Future<void> _postResultWhenFinished(NearbyWarCardTransport transport, String? partnerUserId, int deckSize) async {
    if (partnerUserId == null) return;
    await for (final state in transport.stateStream) {
      if (state.finished) {
        final duration = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds : 0;
        final winnerUserId = state.winnerUserId == kWarCardHostRole
            ? widget.user.id
            : (state.winnerUserId == kWarCardGuestRole ? partnerUserId : null);
        try {
          await GameService.instance.recordWarCardResult(
            widget.game.id,
            roundsCount: state.roundsCount,
            durationSeconds: duration,
            winnerUserId: winnerUserId,
            isTie: state.isTie,
            deckSize: deckSize,
          );
        } catch (_) {
          // Best-effort.
        }
        break;
      }
    }
  }

  @override
  void dispose() {
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
          child: _step == _ConnectStep.choosingDifficulty
              ? WarCardLevelList(theme: theme, onSelected: _startHostGame)
              : Padding(
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
        ),
      ),
    );
  }
}
