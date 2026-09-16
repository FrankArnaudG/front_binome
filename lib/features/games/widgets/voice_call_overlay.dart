import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:showcaseview/showcaseview.dart';

import '../voice_call_service.dart';

/// Bouton flottant "voix en direct" (voir VoiceCallService et demande
/// utilisateur : "ouvrir un micro pour que les joueurs échangent") — un
/// simple tap active/rejoint l'appel dès que le binôme fait de même
/// (négociation WebRTC automatique en arrière-plan) ; une fois connecté,
/// on MAINTIENT le bouton appuyé pour parler (push-to-talk, voir doc de
/// classe de VoiceCallService — jamais de canal ouvert en permanence). Une
/// petite croix apparaît une fois l'appel activé pour raccrocher.
///
/// La caméra (voir demande utilisateur : "et si on veut ajouter une
/// vidéo ?") est un second bouton, séparé et OPTIONNEL — jamais activée
/// par défaut, contrairement au micro qui se négocie dès la connexion.
class VoiceCallOverlay extends StatefulWidget {
  final String boxId;
  final String myUserId;
  final String partnerUserId;
  final bool enabled;
  // Partie en pause (voir demande utilisateur) — le micro reste visible
  // mais grisé et inactif, plutôt que de disparaître : ça évite de faire
  // croire que le bouton a bougé/disparu, tout en rendant clair qu'il faut
  // reprendre la partie pour l'utiliser.
  final bool paused;
  // Solde de pièces du couple épuisé en cours de partie (voir
  // GameWalletGuard/demande utilisateur : "on coupe automatiquement le
  // micro/vidéo") — raccroche l'appel en cours dès que ce flag passe à
  // vrai, comme un appui sur le bouton raccrocher.
  final bool forceEnded;
  // Guide pas-à-pas (voir demande utilisateur : "un guide sur... activer le
  // micro et la camera") — non-null uniquement pour faire apparaître une
  // bulle sur le bouton correspondant. [cameraGuideKey] ne peut s'afficher
  // qu'une fois l'appel connecté (voir bouton caméra ci-dessous, absent de
  // l'arbre avant `VoiceCallStatus.connected`) — la séquence appelante doit
  // donc vérifier que la cible existe avant de l'inclure.
  final GlobalKey? micGuideKey;
  final GlobalKey? cameraGuideKey;

  const VoiceCallOverlay({
    super.key,
    required this.boxId,
    required this.myUserId,
    required this.partnerUserId,
    required this.enabled,
    this.paused = false,
    this.forceEnded = false,
    this.micGuideKey,
    this.cameraGuideKey,
  });

  @override
  State<VoiceCallOverlay> createState() => _VoiceCallOverlayState();
}

class _VoiceCallOverlayState extends State<VoiceCallOverlay> {
  VoiceCallService? _service;
  StreamSubscription<VoiceCallStatus>? _subscription;
  StreamSubscription<bool>? _remoteVideoSubscription;
  VoiceCallStatus _status = VoiceCallStatus.idle;
  bool _talking = false;
  bool _cameraOn = false;
  bool _remoteVideoOn = false;
  bool _togglingCamera = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _createService();
  }

  void _createService() {
    final service = VoiceCallService(
      boxId: widget.boxId,
      myUserId: widget.myUserId,
      partnerUserId: widget.partnerUserId,
    );
    _service = service;
    _subscription = service.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
      // L'appel se termine (raccroché/échoué) : la caméra locale est déjà
      // coupée côté service (voir _teardown), on aligne juste l'état visuel.
      if (status == VoiceCallStatus.idle || status == VoiceCallStatus.failed) {
        setState(() => _cameraOn = false);
      }
    });
    _remoteVideoSubscription = service.remoteVideoActiveStream.listen((active) {
      if (!mounted) return;
      setState(() => _remoteVideoOn = active);
    });
  }

  @override
  void didUpdateWidget(VoiceCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceEnded && !oldWidget.forceEnded) {
      unawaited(_hangup());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _remoteVideoSubscription?.cancel();
    unawaited(_service?.dispose());
    super.dispose();
  }

  Future<void> _onTapMic() async {
    if (widget.paused) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reprends la partie pour utiliser le micro.')),
      );
      return;
    }
    final service = _service;
    if (service == null) return;
    if (_status == VoiceCallStatus.idle || _status == VoiceCallStatus.failed) {
      await service.enable();
    }
  }

  void _onTalkStart() {
    if (widget.paused || _status != VoiceCallStatus.connected) return;
    setState(() => _talking = true);
    _service?.setTalking(true);
  }

  void _onTalkStop() {
    if (!_talking) return;
    setState(() => _talking = false);
    _service?.setTalking(false);
  }

  Future<void> _hangup() async {
    await _service?.disable();
    setState(() {
      _talking = false;
      _cameraOn = false;
    });
  }

  Future<void> _toggleCamera() async {
    final service = _service;
    if (service == null || _status != VoiceCallStatus.connected || _togglingCamera) return;
    setState(() => _togglingCamera = true);
    final result = await service.toggleVideo(!_cameraOn);
    if (!mounted) return;
    setState(() {
      _cameraOn = result;
      _togglingCamera = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    final active = _status != VoiceCallStatus.idle;
    final showVideoArea = _cameraOn || _remoteVideoOn;

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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _wrapGuide(
                    widget.micGuideKey,
                    title: 'Active le micro',
                    description: 'Maintiens ce bouton appuyé pour parler à ton binôme pendant la partie.',
                    child: GestureDetector(
                      onTap: _onTapMic,
                      onTapDown: (_) => _onTalkStart(),
                      onTapUp: (_) => _onTalkStop(),
                      onTapCancel: _onTalkStop,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.paused ? Colors.grey.withValues(alpha: 0.5) : _colorFor(_status, _talking),
                          shape: BoxShape.circle,
                        ),
                        child: widget.paused ? const Icon(Icons.mic_off_rounded, color: Colors.white70, size: 20) : _iconFor(_status),
                      ),
                    ),
                  ),
                  if (active)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: _hangup,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 13),
                        ),
                      ),
                    ),
                ],
              ),
              if (_status == VoiceCallStatus.connected) ...[
                const SizedBox(width: 10),
                _wrapGuide(
                  widget.cameraGuideKey,
                  title: 'Active la caméra',
                  description: "Ajoute la vidéo à l'appel si tu veux vous voir pendant la partie.",
                  child: GestureDetector(
                    onTap: _toggleCamera,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _cameraOn
                            ? Colors.greenAccent.shade400.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.55),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_remoteVideoOn) _videoBox(_service!.remoteRenderer, mirror: false),
        if (_remoteVideoOn && _cameraOn) const SizedBox(width: 6),
        if (_cameraOn) _videoBox(_service!.localRenderer, mirror: true),
      ],
    );
  }

  Widget _videoBox(RTCVideoRenderer renderer, {required bool mirror}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 84,
        height: 112,
        color: Colors.black,
        child: RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
      ),
    );
  }

  Color _colorFor(VoiceCallStatus status, bool talking) {
    if (talking) return Colors.greenAccent.shade400.withValues(alpha: 0.9);
    switch (status) {
      case VoiceCallStatus.idle:
        return Colors.black.withValues(alpha: 0.55);
      case VoiceCallStatus.connecting:
        return Colors.orangeAccent.withValues(alpha: 0.85);
      case VoiceCallStatus.connected:
        return Colors.black.withValues(alpha: 0.55);
      case VoiceCallStatus.failed:
        return Colors.redAccent.withValues(alpha: 0.75);
    }
  }

  Widget _iconFor(VoiceCallStatus status) {
    switch (status) {
      case VoiceCallStatus.idle:
        return const Icon(Icons.mic_off_rounded, color: Colors.white, size: 20);
      case VoiceCallStatus.connecting:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
        );
      case VoiceCallStatus.connected:
        return const Icon(Icons.mic_rounded, color: Colors.white, size: 20);
      case VoiceCallStatus.failed:
        return const Icon(Icons.mic_off_rounded, color: Colors.white, size: 20);
    }
  }
}
