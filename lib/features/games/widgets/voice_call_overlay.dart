import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:showcaseview/showcaseview.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../auth/auth_service.dart';
import '../voice_call_service.dart';

/// Bouton flottant "voix en direct" (voir VoiceCallService et demande
/// utilisateur : "des que la connection est etabli pour jouer, le micro est
/// deja connecte") — la voix se connecte TOUTE SEULE à l'entrée dans la
/// partie, micro ouvert, et se relance seule en cas de coupure. Un tap sur
/// le bouton coupe/rétablit uniquement NOTRE voix sortante (on entend
/// toujours le binôme) : vert = micro ouvert, sombre barré = micro coupé,
/// orange = connexion en cours, rouge = micro non autorisé.
///
/// La caméra (voir demande utilisateur : "et si on veut ajouter une
/// vidéo ?") est un second bouton, séparé et OPTIONNEL — jamais activée
/// par défaut. L'activer invite le binôme (petit "i" à côté de SON bouton
/// caméra, voir [_cameraInviteFrom]) à activer la sienne.
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
  StreamSubscription<CameraInvite>? _inviteSubscription;
  VoiceCallStatus _status = VoiceCallStatus.idle;
  bool _muted = false;
  bool _cameraOn = false;
  bool _remoteVideoOn = false;
  bool _togglingCamera = false;
  // Prénom du binôme qui nous invite à activer notre caméra (null = pas
  // d'invitation en cours) — affiché en bulle "i" à côté du bouton caméra.
  String? _cameraInviteFrom;
  bool _inviteExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _createService();
      if (!widget.forceEnded) unawaited(_service?.enable());
    }
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
      // Liaison interrompue (raccroché/reconnexion) : la caméra locale est
      // déjà coupée côté service (voir _resetPeer), on aligne l'état visuel.
      if (status != VoiceCallStatus.connected) {
        setState(() {
          _cameraOn = false;
          _cameraInviteFrom = null;
        });
      }
    });
    _remoteVideoSubscription = service.remoteVideoActiveStream.listen((active) {
      if (!mounted) return;
      setState(() => _remoteVideoOn = active);
    });
    _inviteSubscription = service.cameraInviteStream.listen((invite) {
      if (!mounted) return;
      setState(() {
        _cameraInviteFrom = invite.cancel || _cameraOn ? null : invite.name;
        _inviteExpanded = !invite.cancel && !_cameraOn;
      });
    });
  }

  @override
  void didUpdateWidget(VoiceCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceEnded && !oldWidget.forceEnded) {
      // Pause/solde épuisé : la voix s'arrête (comme avant)...
      unawaited(_hangup());
    } else if (!widget.forceEnded && oldWidget.forceEnded && widget.enabled) {
      // ...et reprend toute seule au retour dans la partie.
      if (_service == null) _createService();
      unawaited(_service?.enable());
    } else if (widget.enabled && !oldWidget.enabled && _service == null) {
      _createService();
      if (!widget.forceEnded) unawaited(_service?.enable());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _remoteVideoSubscription?.cancel();
    _inviteSubscription?.cancel();
    unawaited(_service?.dispose());
    super.dispose();
  }

  /// Un tap : coupe/rétablit NOTRE micro (la liaison reste établie). Si la
  /// voix n'est pas active (micro refusé, ou arrêtée) : relance la connexion,
  /// ou ouvre les réglages quand c'est l'autorisation qui manque.
  Future<void> _onTapMic() async {
    if (widget.paused) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reprends la partie pour utiliser le micro.')),
      );
      return;
    }
    final service = _service;
    if (service == null) return;
    if (service.permissionDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le micro n'est pas autorisé. Active-le dans les réglages du téléphone.")),
      );
      await openAppSettings();
      return;
    }
    if (_status == VoiceCallStatus.idle || _status == VoiceCallStatus.failed) {
      await service.enable();
      return;
    }
    final muted = !_muted;
    service.setMuted(muted);
    setState(() => _muted = muted);
  }

  Future<void> _hangup() async {
    await _service?.disable();
    if (!mounted) return;
    setState(() => _cameraOn = false);
  }

  Future<void> _toggleCamera() async {
    final service = _service;
    if (service == null || _status != VoiceCallStatus.connected || _togglingCamera) return;
    final before = _cameraOn;
    setState(() => _togglingCamera = true);
    final result = await service.toggleVideo(!before);
    if (!mounted) return;
    setState(() {
      _cameraOn = result;
      _togglingCamera = false;
      // Activer sa propre caméra répond à l'invitation reçue, le cas échéant.
      if (result) _cameraInviteFrom = null;
    });
    // Caméra activée : on invite le binôme à faire de même ; coupée : on
    // annule l'invitation qu'il aurait encore à l'écran.
    if (result != before) {
      final name = (await AuthService.instance.cachedUserIfLoggedIn())?.prenom ?? '';
      unawaited(service.sendCameraInvite(name: name, cancel: !result));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

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
                    title: 'Ton micro',
                    description: 'La voix est déjà connectée. Touche ce bouton pour couper ou rétablir ton micro — tu entends toujours ton binôme.',
                    child: GestureDetector(
                      onTap: _onTapMic,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.paused ? Colors.grey.withValues(alpha: 0.5) : _colorFor(_status, _muted),
                          shape: BoxShape.circle,
                        ),
                        child: widget.paused
                            ? const Icon(Icons.mic_off_rounded, color: Colors.white70, size: 20)
                            : _iconFor(_status, _muted),
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
                  description: "Ajoute la vidéo si tu veux vous voir pendant la partie — ton binôme est invité à activer la sienne.",
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
                if (_cameraInviteFrom != null) ...[
                  const SizedBox(width: 8),
                  _buildCameraInvite(),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Petit "i" à côté du bouton caméra : le binôme nous invite à activer la
  /// nôtre. Un tap déplie/replie le message ; il disparaît dès qu'on active
  /// notre caméra ou que le binôme coupe la sienne.
  Widget _buildCameraInvite() {
    final name = (_cameraInviteFrom ?? '').trim();
    final text = name.isEmpty ? "Ton binôme t'invite à activer ta caméra" : "$name t'invite à activer ta caméra";
    return GestureDetector(
      onTap: () => setState(() => _inviteExpanded = !_inviteExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(maxWidth: 200),
        padding: EdgeInsets.symmetric(horizontal: _inviteExpanded ? 10 : 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_rounded, color: Colors.lightBlueAccent, size: 18),
            if (_inviteExpanded) ...[
              const SizedBox(width: 6),
              Flexible(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.25))),
            ],
          ],
        ),
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

  Color _colorFor(VoiceCallStatus status, bool muted) {
    switch (status) {
      case VoiceCallStatus.idle:
        return Colors.black.withValues(alpha: 0.55);
      case VoiceCallStatus.connecting:
        return Colors.orangeAccent.withValues(alpha: 0.85);
      case VoiceCallStatus.connected:
        return muted ? Colors.black.withValues(alpha: 0.55) : Colors.greenAccent.shade400.withValues(alpha: 0.9);
      case VoiceCallStatus.failed:
        return Colors.redAccent.withValues(alpha: 0.75);
    }
  }

  Widget _iconFor(VoiceCallStatus status, bool muted) {
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
        return Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded, color: Colors.white, size: 20);
      case VoiceCallStatus.failed:
        return const Icon(Icons.mic_off_rounded, color: Colors.white, size: 20);
    }
  }
}
