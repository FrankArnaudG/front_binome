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
import 'battleship_difficulty_screen.dart';
import 'battleship_placement_screen.dart';
import 'battleship_transport_nearby.dart';

const _kNearbyServiceId = 'app.binome.battleship';

/// Mode "présentiel connecté" : établit la connexion Bluetooth/WiFi Direct
/// (voir NearbyBattleshipTransport) puis, une fois connecté, l'hôte choisit
/// la taille de grille (l'invité attend simplement — elle lui arrive dans
/// le premier message `state`, voir NearbyBattleshipTransport.guest) avant
/// de pousser l'écran de PLACEMENT — jamais directement le plateau de
/// combat, chacun place sa flotte sur SON PROPRE appareil (pas de "passe le
/// téléphone" nécessaire ici, contrairement au pass-and-play).
class BattleshipNearbyConnectScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const BattleshipNearbyConnectScreen({super.key, required this.game, required this.user});

  @override
  State<BattleshipNearbyConnectScreen> createState() => _BattleshipNearbyConnectScreenState();
}

enum _ConnectStep { choose, hosting, discovering, connected, choosingDifficulty }

class _BattleshipNearbyConnectScreenState extends State<BattleshipNearbyConnectScreen> {
  final _nearby = Nearby();
  _ConnectStep _step = _ConnectStep.choose;
  String? _error;
  String? _connectedEndpointId;
  bool _isHost = false;
  NearbyBattleshipTransport? _transport;

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
      setState(() {
        _connectedEndpointId = endpointId;
        _step = _isHost ? _ConnectStep.choosingDifficulty : _ConnectStep.connected;
      });

      if (!_isHost) {
        // L'invité attend la taille de grille : construit tout de suite un
        // transport en écoute, poussé dès la réception du premier message
        // `state` (voir NearbyBattleshipTransport.guest).
        final transport = NearbyBattleshipTransport.guest(nearby: _nearby, endpointId: endpointId);
        _transport = transport;
        transport.stateStream.first.then((_) {
          if (mounted) _openPlacement(transport);
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

  void _startHostGame(int gridSize) {
    final endpointId = _connectedEndpointId;
    if (endpointId == null) return;
    final transport = NearbyBattleshipTransport.host(nearby: _nearby, endpointId: endpointId, gridSize: gridSize);
    _transport = transport;
    _openPlacement(transport);
  }

  void _openPlacement(NearbyBattleshipTransport transport) {
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(widget.user.id);
    final myRole = _isHost ? kBattleshipHostRole : kBattleshipGuestRole;
    final partnerRole = _isHost ? kBattleshipGuestRole : kBattleshipHostRole;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BattleshipPlacementScreen(
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

  Future<void> _postResultWhenFinished(NearbyBattleshipTransport transport, String? partnerUserId) async {
    if (partnerUserId == null) return;
    await for (final state in transport.stateStream) {
      if (state.finished) {
        final duration = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds : 0;
        final winnerUserId = state.winnerUserId == kBattleshipHostRole
            ? widget.user.id
            : (state.winnerUserId == kBattleshipGuestRole ? partnerUserId : null);
        try {
          await GameService.instance.recordBattleshipResult(
            widget.game.id,
            movesCount: state.movesCount,
            durationSeconds: duration,
            winnerUserId: winnerUserId,
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
              ? BattleshipGridSizeList(theme: theme, onSelected: _startHostGame)
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
