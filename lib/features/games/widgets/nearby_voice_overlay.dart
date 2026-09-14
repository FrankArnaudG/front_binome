import 'dart:async';

import 'package:flutter/material.dart';

import '../nearby/nearby_comms.dart';

/// Bouton "voix en direct" pour le mode présentiel connecté (voir
/// NearbyComms) — push-to-talk comme VoiceCallOverlay (maintenir appuyé
/// pour parler), mais SANS WebRTC ni serveur de signalisation : la voix
/// transite uniquement par la connexion Bluetooth/Wifi Direct déjà utilisée
/// par le jeu (voir demande utilisateur). Remplace VoiceCallOverlay pour ce
/// mode, jamais affiché en même temps (voir *_board_screen.dart : l'un ou
/// l'autre selon `commentsBoxId`/`nearbyComms`).
class NearbyVoiceOverlay extends StatefulWidget {
  final NearbyComms? comms;
  final bool enabled;
  final bool paused;

  const NearbyVoiceOverlay({super.key, required this.comms, required this.enabled, this.paused = false});

  @override
  State<NearbyVoiceOverlay> createState() => _NearbyVoiceOverlayState();
}

class _NearbyVoiceOverlayState extends State<NearbyVoiceOverlay> {
  bool _talking = false;
  bool _starting = false;

  Future<void> _onTalkStart() async {
    if (widget.paused || _starting || _talking) return;
    final comms = widget.comms;
    if (comms == null) return;
    setState(() => _starting = true);
    final ok = await comms.startTalking();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _talking = ok;
    });
  }

  Future<void> _onTalkStop() async {
    if (!_talking) return;
    setState(() => _talking = false);
    await widget.comms?.stopTalking();
  }

  @override
  void dispose() {
    if (_talking) unawaited(widget.comms?.stopTalking());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.comms == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      bottom: 24,
      child: GestureDetector(
        onTapDown: (_) => _onTalkStart(),
        onTapUp: (_) => _onTalkStop(),
        onTapCancel: _onTalkStop,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.paused
                ? Colors.grey.withValues(alpha: 0.5)
                : (_talking ? Colors.redAccent : Colors.black.withValues(alpha: 0.55)),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.paused ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
