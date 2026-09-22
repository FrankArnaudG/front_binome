import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

import '../nearby/nearby_comms.dart';

/// Bouton "voix et vidéo en direct" pour le mode présentiel connecté (voir
/// NearbyComms) — mic et caméra tous deux à bascule (tap pour activer/désactiver), même
/// principe/disposition que VoiceCallOverlay, mais SANS WebRTC ni serveur
/// de signalisation : voix et vidéo transitent uniquement par la connexion
/// Bluetooth/Wifi Direct déjà utilisée par le jeu (voir demande
/// utilisateur). Remplace VoiceCallOverlay pour ce mode, jamais affiché en
/// même temps (voir *_board_screen.dart : l'un ou l'autre selon
/// `commentsBoxId`/`nearbyComms`).
class NearbyVoiceOverlay extends StatefulWidget {
  final NearbyComms? comms;
  final bool enabled;
  final bool paused;
  // Guide pas-à-pas (voir demande utilisateur : "un guide sur... activer le
  // micro et la camera") — non-null uniquement pour faire apparaître une
  // bulle sur le bouton correspondant.
  final GlobalKey? micGuideKey;
  final GlobalKey? cameraGuideKey;

  const NearbyVoiceOverlay({
    super.key,
    required this.comms,
    required this.enabled,
    this.paused = false,
    this.micGuideKey,
    this.cameraGuideKey,
  });

  @override
  State<NearbyVoiceOverlay> createState() => _NearbyVoiceOverlayState();
}

class _NearbyVoiceOverlayState extends State<NearbyVoiceOverlay> {
  bool _talking = false;
  bool _starting = false;
  bool _cameraOn = false;
  bool _togglingCamera = false;
  Uint8List? _remoteFrame;
  StreamSubscription<Uint8List?>? _remoteFrameSubscription;

  @override
  void initState() {
    super.initState();
    _remoteFrameSubscription = widget.comms?.remoteVideoFrames.listen((bytes) {
      if (mounted) setState(() => _remoteFrame = bytes);
    });
  }

  @override
  void didUpdateWidget(NearbyVoiceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Coupe micro/caméra dès la mise en pause (voir demande utilisateur :
    // "couper tout les procecusse lour comme l'audio, la video" à la
    // pause) — même principe que VoiceCallOverlay.forceEnded, mais ici
    // directement sur `paused` : pas de connexion à "raccrocher" comme en
    // WebRTC, juste à arrêter la capture locale.
    if (widget.paused && !oldWidget.paused) {
      if (_talking) unawaited(_onToggleTalk());
      if (_cameraOn) unawaited(_toggleCamera());
    }
  }

  // Bascule (tap pour activer/désactiver), comme le bouton caméra — remplace
  // l'ancien mode "maintenir appuyé" suite à demande utilisateur : "je dois
  // cliquer plusieurs fois pour que ça s'active".
  Future<void> _onToggleTalk() async {
    if (widget.paused || _starting) return;
    final comms = widget.comms;
    if (comms == null) return;
    if (_talking) {
      setState(() => _talking = false);
      await comms.stopTalking();
      return;
    }
    setState(() => _starting = true);
    final ok = await comms.startTalking();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _talking = ok;
    });
  }

  Future<void> _toggleCamera() async {
    final comms = widget.comms;
    if (comms == null || _togglingCamera) return;
    // Autorise toujours à ÉTEINDRE (y compris pendant la pause, voir
    // didUpdateWidget), mais jamais à ALLUMER tant que c'est en pause —
    // même garde-fou que le micro (voir widget.paused ci-dessous).
    if (widget.paused && !_cameraOn) return;
    setState(() => _togglingCamera = true);
    if (_cameraOn) {
      await comms.stopVideo();
      if (!mounted) return;
      setState(() {
        _cameraOn = false;
        _togglingCamera = false;
      });
    } else {
      final ok = await comms.startVideo();
      if (!mounted) return;
      setState(() {
        _cameraOn = ok;
        _togglingCamera = false;
      });
    }
  }

  @override
  void dispose() {
    _remoteFrameSubscription?.cancel();
    if (_talking) unawaited(widget.comms?.stopTalking());
    if (_cameraOn) unawaited(widget.comms?.stopVideo());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.comms == null) return const SizedBox.shrink();

    final showVideoArea = _cameraOn || _remoteFrame != null;

    return Positioned(
      left: 16,
      bottom: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showVideoArea) ...[
            _buildVideoPreviews(),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _wrapGuide(
                widget.micGuideKey,
                title: 'Active le micro',
                description: 'Appuie sur ce bouton pour activer ou couper le micro pendant la partie.',
                child: GestureDetector(
                  onTap: _onToggleTalk,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      // Vert quand actif — même convention que le bouton caméra juste en dessous et
                      // que le micro du mode à distance (voir VoiceCallOverlay._colorFor). Corrigé
                      // suite à demande utilisateur : "normalement cest en vert" (c'était en rouge).
                      color: widget.paused
                          ? Colors.grey.withValues(alpha: 0.5)
                          : (_talking ? Colors.greenAccent.shade400.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.55)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.paused ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _wrapGuide(
                widget.cameraGuideKey,
                title: 'Active la caméra',
                description: "Ajoute la vidéo si tu veux vous voir pendant la partie.",
                child: GestureDetector(
                  onTap: _toggleCamera,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.paused
                          ? Colors.grey.withValues(alpha: 0.5)
                          : (_cameraOn ? Colors.greenAccent.shade400.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.55)),
                      shape: BoxShape.circle,
                    ),
                    child: _togglingCamera
                        ? const Padding(
                            padding: EdgeInsets.all(9),
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : Icon(
                            _cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wrapGuide(GlobalKey? key, {required String title, required String description, required Widget child}) {
    if (key == null) return child;
    return Showcase(key: key, title: title, description: description, targetShapeBorder: const CircleBorder(), child: child);
  }

  Widget _buildVideoPreviews() {
    final remoteFrame = _remoteFrame;
    final controller = widget.comms?.cameraController;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (remoteFrame != null) _videoBox(child: Image.memory(remoteFrame, fit: BoxFit.cover, gaplessPlayback: true)),
        if (remoteFrame != null && _cameraOn) const SizedBox(width: 6),
        if (_cameraOn && controller != null && controller.value.isInitialized)
          _videoBox(child: CameraPreview(controller)),
      ],
    );
  }

  Widget _videoBox({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(width: 84, height: 112, color: Colors.black, child: child),
    );
  }
}
