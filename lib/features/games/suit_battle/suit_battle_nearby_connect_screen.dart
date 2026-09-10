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
import 'suit_battle_board_screen.dart';
import 'suit_battle_transport_nearby.dart';

const _kNearbyServiceId = 'app.binome.suit_battle';

/// Mode "présentiel connecté" : établit la connexion Bluetooth/WiFi Direct
/// (voir NearbySuitBattleTransport) puis pousse directement le plateau —
/// contrairement à "Bataille", pas de choix de palier de paquet ici (une
/// seule taille : 52 cartes + 2 Jokers, voir SuitBattleEngine) — copie
/// structurelle conforme de WarCardNearbyConnectScreen.
class SuitBattleNearbyConnectScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const SuitBattleNearbyConnectScreen({super.key, required this.game, required this.user});

  @override
  State<SuitBattleNearbyConnectScreen> createState() => _SuitBattleNearbyConnectScreenState();
}

enum _ConnectStep { choose, hosting, discovering, connected }

class _SuitBattleNearbyConnectScreenState extends State<SuitBattleNearbyConnectScreen> {
  final _nearby = Nearby();
  _ConnectStep _step = _ConnectStep.choose;
  String? _error;
  bool _isHost = false;
  NearbySuitBattleTransport? _transport;

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
        final transport = NearbySuitBattleTransport.host(nearby: _nearby, endpointId: endpointId);
        _transport = transport;
        _openBoard(transport);
      } else {
        _nearby.stopDiscovery();
        setState(() => _step = _ConnectStep.connected);
        final transport = NearbySuitBattleTransport.guest(nearby: _nearby, endpointId: endpointId);
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
    });
  }

  void _openBoard(NearbySuitBattleTransport transport) {
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(widget.user.id);
    final myRole = _isHost ? kSuitBattleHostRole : kSuitBattleGuestRole;
    final partnerRole = _isHost ? kSuitBattleGuestRole : kSuitBattleHostRole;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SuitBattleBoardScreen(
          game: widget.game,
          user: widget.user,
          transport: transport,
          playerNames: {myRole: widget.user.prenom, partnerRole: partner?.prenom ?? LocaleScope.t(context, 'memory_score_player_fallback')},
          playerAvatars: {myRole: widget.user.avatar, partnerRole: partner?.avatar},
        ),
      ),
    );

    if (_isHost) {
      unawaited(_postResultWhenFinished(transport, partner?.id));
    }
  }

  Future<void> _postResultWhenFinished(NearbySuitBattleTransport transport, String? partnerUserId) async {
    if (partnerUserId == null) return;
    await for (final state in transport.stateStream) {
      if (state.finished) {
        final duration = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds : 0;
        final winnerUserId = state.winnerUserId == kSuitBattleHostRole
            ? widget.user.id
            : (state.winnerUserId == kSuitBattleGuestRole ? partnerUserId : null);
        try {
          await GameService.instance.recordSuitBattleResult(
            widget.game.id,
            roundsCount: state.roundsCount,
            durationSeconds: duration,
            winnerUserId: winnerUserId,
            isTie: state.isTie,
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
          child: Padding(
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
