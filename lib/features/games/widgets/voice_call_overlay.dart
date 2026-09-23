import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:showcaseview/showcaseview.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../auth/auth_service.dart';
import '../../box/box_scope.dart';
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
  // Coupé par défaut (voir VoiceCallService, doc de classe : "un simple
  // clic pour qu'il passe au vert") — reflète l'état initial du service.
  bool _muted = true;
  bool _cameraOn = false;
  bool _remoteVideoOn = false;
  bool _togglingCamera = false;
  // Prénom du binôme qui nous invite à activer notre caméra (null = pas
  // d'invitation en cours) — affiché en bulle "i" à côté du bouton caméra.
  String? _cameraInviteFrom;
  bool _inviteExpanded = false;
  // Petite info sur l'état de la voix pendant que le bouton tourne (attente
  // du binôme / connexion / reconnexion) : dépliée ~4 s à chaque changement,
  // puis repliée en "i" (un tap la rouvre).
  StreamSubscription<void>? _changesSubscription;
  Timer? _noteTimer;
  bool _noteExpanded = false;

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
      _flashNote();
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
    _changesSubscription = service.changes.listen((_) => _flashNote());
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
    _changesSubscription?.cancel();
    _noteTimer?.cancel();
    unawaited(_service?.dispose());
    super.dispose();
  }

  void _flashNote() {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() => _noteExpanded = true);
    _noteTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _noteExpanded = false);
    });
  }

  /// Texte d'état affiché à côté du bouton tant que la voix n'est pas
  /// connectée (`null` = rien à dire : connecté, arrêté ou refusé).
  String? _statusNote() {
    final service = _service;
    if (service == null || widget.paused || _status != VoiceCallStatus.connecting) return null;
    if (service.partnerReady && service.everConnected) return 'Connexion perdue, reconnexion…';
    if (!service.partnerReady) {
      final name = BoxScope.of(context).currentBox?.partner?.prenom.trim() ?? '';
      return name.isEmpty ? 'En attente de ton binôme… La voix démarre dès son arrivée' : 'En attente de $name… La voix démarre dès son arrivée';
    }
    return 'Connexion de la voix…';
  }

  /// Feuille modale (voir demande utilisateur : "afficher d'abord un
  /// modal qui sort du bas... avec deux boutons, l'un pour fermer et
  /// l'autre pour aller activer") — remplace l'ancien SnackBar suivi
  /// d'une redirection AUTOMATIQUE vers les réglages, qui surprenait
  /// l'utilisateur (aucune confirmation avant de quitter l'app).
  Future<void> _showMicPermissionSheet() async {
    final goToSettings = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mic_off_rounded, size: 36, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                "Micro non autorisé",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                "Ton micro n'est pas autorisé pour cette app. Active-le dans les réglages du téléphone pour parler avec ton binôme.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Fermer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Activer dans les réglages'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (goToSettings == true) await openAppSettings();
  }

  /// Un tap : coupe/rétablit NOTRE micro (la liaison reste établie). Si la
  /// voix n'est pas active (micro refusé, ou arrêtée) : relance la connexion,
  /// ou ouvre les réglages quand c'est l'autorisation manque.
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
      await _showMicPermissionSheet();
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
              if (_statusNote() case final note?) ...[
                const SizedBox(width: 8),
                _infoBubble(note, expanded: _noteExpanded, onTap: () => _noteExpanded ? setState(() => _noteExpanded = false) : _flashNote()),
              ],
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
    return _infoBubble(text, expanded: _inviteExpanded, onTap: () => setState(() => _inviteExpanded = !_inviteExpanded));
  }

  /// Bulle "i" repliable : icône seule, ou icône + message quand [expanded].
  Widget _infoBubble(String text, {required bool expanded, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(maxWidth: 220),
        padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_rounded, color: Colors.lightBlueAccent, size: 18),
            if (expanded) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
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
