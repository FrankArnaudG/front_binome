import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/realtime_client.dart';
import 'game_service.dart';

/// Voix en direct pendant une partie à deux téléphones (voir demande
/// utilisateur : "ouvrir un micro pour que les joueurs échangent") — appel
/// audio WebRTC en push-to-talk : l'audio ne transite JAMAIS par notre
/// backend, seule la négociation (offre/réponse SDP, candidats ICE) passe
/// par le canal temps réel déjà utilisé par le reste du jeu (voir
/// VoiceSignal côté back).
///
/// Déroulé (voir demande utilisateur : "des que la connection est etabli
/// pour jouer, le micro est deja connecte") : la voix s'active TOUTE SEULE à
/// l'entrée dans la partie ([enable], appelé par l'overlay). Dès que LES
/// DEUX sont prêts, la connexion WebRTC se négocie automatiquement (celui
/// des deux dont l'identifiant est lexicographiquement le plus petit
/// devient l'offreur — départage déterministe, évite une offre en double
/// sans handshake supplémentaire). Le micro est OUVERT par défaut ;
/// [setMuted] coupe seulement la voix SORTANTE, la liaison reste établie
/// (on continue d'entendre le binôme). En cas de coupure, la connexion est
/// relancée automatiquement (voir [_scheduleReconnect]) tant que personne
/// n'a raccroché.
enum VoiceCallStatus { idle, connecting, connected, failed }

/// Ce que le binôme demande via un signal `camera_invite` (voir
/// [VoiceCallService.cameraInviteStream]) : `name` = prénom de l'invitant,
/// `cancel` = il vient de couper sa caméra, l'invitation n'a plus lieu d'être.
class CameraInvite {
  final String name;
  final bool cancel;
  const CameraInvite({required this.name, this.cancel = false});
}

class VoiceCallService {
  final String boxId;
  final String myUserId;
  final String partnerUserId;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _iAmReady = false;
  bool _partnerReady = false;
  bool _muted = false;
  bool get isMuted => _muted;
  // Vrai si l'autorisation du micro a été refusée (bouton rouge avec
  // explication, voir VoiceCallOverlay) — le seul cas où "échec" reste
  // affiché : les coupures réseau, elles, sont rattrapées automatiquement.
  bool permissionDenied = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  // Évite deux négociations simultanées (voice_ready + réponse reçus presque
  // ensemble) qui créaient deux connexions et deux offres — cause d'une
  // liaison "qui tourne indéfiniment" après une pause.
  bool _negotiationStarted = false;
  Future<void>? _pcFuture;
  Timer? _watchdog;
  // Vrai dès qu'on a été connecté au moins une fois : distingue "on attend"
  // de "connexion perdue, on reconnecte" (voir VoiceCallOverlay).
  bool everConnected = false;
  bool get partnerReady => _partnerReady;
  final _changesController = StreamController<void>.broadcast();

  /// Émis quand l'état visible change sans que le statut change (le binôme
  /// arrive, une reconnexion démarre...) — voir VoiceCallOverlay.
  Stream<void> get changes => _changesController.stream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  final _cameraInviteController = StreamController<CameraInvite>.broadcast();
  Stream<CameraInvite> get cameraInviteStream => _cameraInviteController.stream;

  // Vidéo — voir doc de classe : OPTIONNELLE, jamais activée par défaut
  // (voir demande utilisateur : garder l'appel voix léger comme base, la
  // caméra reste un choix conscient de chaque côté). Contrairement au
  // micro (coupé par défaut mais négocié dès le départ), la piste vidéo
  // n'est ajoutée qu'à l'activation — ce qui déclenche une RENÉGOCIATION
  // (nouvel aller-retour offre/réponse sur la connexion déjà établie,
  // voir [_renegotiate]) plutôt qu'un nouvel appel.
  MediaStream? _localVideoStream;
  MediaStreamTrack? _localVideoTrack;
  bool _videoEnabled = false;
  bool get isVideoEnabled => _videoEnabled;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  final _remoteVideoActiveController = StreamController<bool>.broadcast();
  Stream<bool> get remoteVideoActiveStream => _remoteVideoActiveController.stream;

  final _statusController = StreamController<VoiceCallStatus>.broadcast();
  Stream<VoiceCallStatus> get statusStream => _statusController.stream;
  VoiceCallStatus _status = VoiceCallStatus.idle;
  VoiceCallStatus get status => _status;

  bool get isEnabled => _iAmReady;

  VoiceCallService({required this.boxId, required this.myUserId, required this.partnerUserId}) {
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _watchdog?.cancel();
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    final wasEnabled = _iAmReady;
    _iAmReady = false;
    await _teardown();
    if (_renderersReady) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    }
    if (wasEnabled) {
      unawaited(GameService.instance.sendVoiceSignal('voice_hangup', const {}));
    }
  }

  Future<void> enable() async {
    if (_iAmReady) return;
    final permission = await Permission.microphone.request();
    debugPrint('VoiceCall: permission micro = $permission');
    if (!permission.isGranted) {
      permissionDenied = true;
      _setStatus(VoiceCallStatus.failed);
      return;
    }
    permissionDenied = false;
    _iAmReady = true;
    _negotiationStarted = false;
    _pcFuture = null;
    _setStatus(VoiceCallStatus.connecting);
    debugPrint('VoiceCall: enable() — envoi voice_ready (partnerReady=$_partnerReady)');
    await GameService.instance.sendVoiceSignal('voice_ready', const {});
    if (_partnerReady) await _maybeStartNegotiation();
  }

  Future<void> disable() async {
    _reconnectTimer?.cancel();
    if (!_iAmReady) return;
    _iAmReady = false;
    await GameService.instance.sendVoiceSignal('voice_hangup', const {});
    await _teardown();
  }

  /// Coupe/rétablit SEULEMENT la voix sortante (voir demande utilisateur :
  /// "je coupe le micro et je salue ma voisine") — la liaison reste établie,
  /// on entend toujours le binôme. Mémorisé pour survivre à une reconnexion.
  void setMuted(bool muted) {
    _muted = muted;
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final track in tracks) {
      track.enabled = !muted;
    }
  }

  /// Invite le binôme à activer SA caméra (petit "i" à côté de son bouton
  /// caméra, voir VoiceCallOverlay) — `cancel` annule l'invitation (on vient
  /// de couper la nôtre).
  Future<void> sendCameraInvite({required String name, bool cancel = false}) =>
      GameService.instance.sendVoiceSignal('camera_invite', {'name': name, 'cancel': cancel});

  /// Active/coupe la caméra — uniquement possible une fois l'appel
  /// CONNECTÉ (voir [VoiceCallStatus.connected]), pour ne pas complexifier
  /// la négociation initiale. Contrairement au micro, la vidéo tourne en
  /// continu une fois activée (pas de push-to-talk vidéo) : le bouton
  /// caméra EST le contrôle.
  Future<bool> toggleVideo(bool enabled) async {
    if (enabled == _videoEnabled || _pc == null) return _videoEnabled;
    if (enabled) {
      final permission = await Permission.camera.request();
      debugPrint('VoiceCall: permission caméra = $permission');
      if (!permission.isGranted) return _videoEnabled;
      await _ensureRenderers();
      try {
        _localVideoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': 'user'},
        });
        _localVideoTrack = _localVideoStream!.getVideoTracks().first;
        localRenderer.srcObject = _localVideoStream;
        await _pc!.addTrack(_localVideoTrack!, _localVideoStream!);
        _videoEnabled = true;
      } catch (e, st) {
        debugPrint('VoiceCall: ÉCHEC activation caméra — $e\n$st');
        return _videoEnabled;
      }
    } else {
      final track = _localVideoTrack;
      if (track != null) {
        final senders = await _pc!.getSenders();
        for (final sender in senders) {
          if (sender.track?.id == track.id) await _pc!.removeTrack(sender);
        }
        await track.stop();
      }
      localRenderer.srcObject = null;
      await _localVideoStream?.dispose();
      _localVideoStream = null;
      _localVideoTrack = null;
      _videoEnabled = false;
    }
    return _videoEnabled;
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  /// Un aller-retour offre/réponse SUPPLÉMENTAIRE sur la connexion déjà
  /// établie (voir [toggleVideo]) — pas un nouvel appel. Réutilise le même
  /// signal 'offer'/'answer' que la négociation initiale : côté
  /// récepteur, [_onOffer] fonctionne à l'identique (sa garde `_pc != null`
  /// dans [_ensurePeerConnection] fait que la connexion existante est
  /// simplement réutilisée).
  Future<void> _renegotiate() async {
    if (_pc == null) return;
    if (_pc!.signalingState != RTCSignalingState.RTCSignalingStateStable) return;
    try {
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      debugPrint('VoiceCall: renégociation — offre créée, envoi...');
      await GameService.instance.sendVoiceSignal('offer', {'sdp': _encodeSdp(offer.sdp), 'type': offer.type});
    } catch (e, st) {
      debugPrint('VoiceCall: ÉCHEC renégociation — $e\n$st');
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'VoiceSignal') return;
    final data = event.data;
    if (data == null) return;
    debugPrint('VoiceCall: reçu VoiceSignal from=${data['from_user_id']} type=${data['type']} (attendu partner=$partnerUserId)');
    // Ignore notre propre écho — le canal presence-box renvoie aussi
    // l'évènement à son émetteur (voir GameCommentSent, même principe).
    if ((data['from_user_id'] as String?) != partnerUserId) return;

    final type = data['type'] as String?;
    // `payload` peut arriver comme un tableau JSON `[]` (pas un objet `{}`)
    // quand PHP encode un tableau associatif VIDE (voice_ready/voice_hangup
    // n'envoient rien) — `json_encode([])` donne `[]`, pas `{}`. Un cast
    // direct `as Map?` plante dans ce cas (`List` n'est pas `Map`) ; on
    // retombe simplement sur un objet vide plutôt que de propager l'erreur.
    final rawPayload = data['payload'];
    final payload = rawPayload is Map ? rawPayload.cast<String, dynamic>() : <String, dynamic>{};
    switch (type) {
      case 'voice_ready':
        final wasReady = _partnerReady;
        final isReply = payload['reply'] == true;
        _partnerReady = true;
        if (!wasReady) _changesController.add(null);
        if (!_iAmReady) break;
        // Le binôme était déjà dans la partie quand on est arrivé : il n'a
        // jamais reçu NOTRE voice_ready, on lui répond (une seule fois, le
        // drapeau `reply` évite tout ping-pong).
        if (!wasReady && !isReply) {
          unawaited(GameService.instance.sendVoiceSignal('voice_ready', const {'reply': true}));
        }
        // voice_ready "frais" alors qu'on le croyait déjà là : il a relancé
        // sa connexion (reconnexion/retour dans l'app) — notre côté est
        // périmé, on repart de zéro plutôt que d'attendre un délai.
        if (wasReady && !isReply && (_pc != null || _negotiationStarted)) {
          unawaited(_resetPeer().then((_) => _maybeStartNegotiation()));
        } else {
          unawaited(_maybeStartNegotiation());
        }
      case 'camera_invite':
        _cameraInviteController.add(CameraInvite(
          name: (payload['name'] as String?) ?? '',
          cancel: payload['cancel'] == true,
        ));
      case 'offer':
        unawaited(_onOffer(payload));
      case 'answer':
        unawaited(_onAnswer(payload));
      case 'ice_candidate':
        unawaited(_onRemoteIceCandidate(payload));
      case 'voice_hangup':
        // Le binôme a quitté la partie : on garde notre voix "prête" et on
        // attend son retour (voice_ready) — pas de reconnexion en boucle.
        _partnerReady = false;
        _reconnectTimer?.cancel();
        _watchdog?.cancel();
        unawaited(_resetPeer().then((_) {
          if (_iAmReady) _setStatus(VoiceCallStatus.connecting);
          _changesController.add(null);
        }));
    }
  }

  Future<void> _maybeStartNegotiation() async {
    if (_pc != null || _negotiationStarted) return; // déjà en cours/connecté
    _negotiationStarted = true;
    _armWatchdog();
    final isOfferer = myUserId.compareTo(partnerUserId) < 0;
    debugPrint('VoiceCall: _maybeStartNegotiation — isOfferer=$isOfferer');
    try {
      await _ensurePeerConnection();
      if (isOfferer) {
        final offer = await _pc!.createOffer({});
        await _pc!.setLocalDescription(offer);
        debugPrint('VoiceCall: offre créée, sdp.length=${offer.sdp?.length} type=${offer.type} — envoi...');
        await GameService.instance.sendVoiceSignal('offer', {'sdp': _encodeSdp(offer.sdp), 'type': offer.type});
      }
    } catch (e, st) {
      debugPrint('VoiceCall: ÉCHEC négociation — $e\n$st');
      _negotiationStarted = false;
      _setStatus(VoiceCallStatus.connecting);
      _scheduleReconnect(Duration.zero);
    }
  }

  /// Filet de sécurité : si la liaison n'est pas établie 20 s après le début
  /// d'une négociation (offre perdue, binôme parti sans prévenir...), on
  /// relance au lieu de tourner indéfiniment.
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 20), () {
      if (_iAmReady && _partnerReady && _status != VoiceCallStatus.connected) {
        _scheduleReconnect(Duration.zero);
      }
    });
  }

  // Un seul appelant crée la connexion, les autres attendent la même création.
  Future<void> _ensurePeerConnection() => _pcFuture ??= _createPeerConnection();

  Future<void> _createPeerConnection() async {
    final iceServers = await GameService.instance.fetchIceServers();
    debugPrint('VoiceCall: iceServers = $iceServers');
    final pc = await createPeerConnection({'iceServers': iceServers});
    _pc = pc;

    debugPrint('VoiceCall: demande getUserMedia...');
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    debugPrint('VoiceCall: getUserMedia OK, pistes=${_localStream!.getAudioTracks().length}');
    // Ouvert par défaut, sauf si on l'avait coupé avant une reconnexion.
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_muted;
      await pc.addTrack(track, _localStream!);
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(GameService.instance.sendVoiceSignal('ice_candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
    };
    // Déclenché localement quand ON ajoute/retire une piste (voir
    // [toggleVideo]) — SEUL le côté qui a modifié ses pistes voit cet
    // évènement et ré-émet une offre ; l'autre reçoit simplement cette
    // offre via [_onOffer], comme pour la négociation initiale.
    pc.onRenegotiationNeeded = () => unawaited(_renegotiate());
    pc.onTrack = (event) {
      if (event.track.kind != 'video' || event.streams.isEmpty) return;
      unawaited(_ensureRenderers().then((_) {
        remoteRenderer.srcObject = event.streams.first;
        _remoteVideoActiveController.add(true);
      }));
    };
    pc.onRemoveTrack = (stream, track) {
      if (track.kind != 'video') return;
      remoteRenderer.srcObject = null;
      _remoteVideoActiveController.add(false);
    };
    pc.onConnectionState = (state) {
      debugPrint('VoiceCall: connectionState => $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _reconnectTimer?.cancel();
          _watchdog?.cancel();
          _reconnectAttempts = 0;
          everConnected = true;
          _setStatus(VoiceCallStatus.connected);
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Souvent passager (micro-coupure, changement de réseau) : on
          // laisse quelques secondes à WebRTC pour se rétablir seul avant de
          // tout relancer.
          if (_iAmReady) {
            _setStatus(VoiceCallStatus.connecting);
            _scheduleReconnect(const Duration(seconds: 6));
          }
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          if (_iAmReady) {
            _setStatus(VoiceCallStatus.connecting);
            _scheduleReconnect(Duration.zero);
          }
        default:
          break;
      }
    };
  }

  /// Relance la liaison après une coupure (voir demande utilisateur : "si ca
  /// se deconnecte, relancer a chaque fois automatiquement") : on repart d'une
  /// connexion neuve et on prévient le binôme par un voice_ready "frais", qui
  /// fait de même de son côté. Délai croissant (2s → 15s max) pour ne pas
  /// marteler le serveur si le réseau reste absent.
  void _scheduleReconnect(Duration minDelay) {
    _reconnectTimer?.cancel();
    if (!_iAmReady) return;
    final backoff = Duration(seconds: (2 << _reconnectAttempts.clamp(0, 3)).clamp(2, 15));
    final delay = minDelay == Duration.zero ? Duration.zero : (minDelay > backoff ? minDelay : backoff);
    _reconnectTimer = Timer(delay, () async {
      if (!_iAmReady || _status == VoiceCallStatus.connected) return;
      _reconnectAttempts++;
      _changesController.add(null);
      debugPrint('VoiceCall: reconnexion automatique (tentative $_reconnectAttempts)');
      await _resetPeer();
      if (!_iAmReady) return;
      _setStatus(VoiceCallStatus.connecting);
      try {
        await GameService.instance.sendVoiceSignal('voice_ready', const {});
      } catch (_) {
        // Réseau absent : la prochaine tentative repassera par ici.
      }
      if (_partnerReady) await _maybeStartNegotiation();
      // Toujours pas connecté après cette tentative : on en programme une autre.
      _reconnectTimer = Timer(Duration(seconds: 4 + _reconnectAttempts.clamp(0, 6) * 2), () {
        if (_iAmReady && _status != VoiceCallStatus.connected) _scheduleReconnect(Duration.zero);
      });
    });
  }

  /// Ferme la connexion WebRTC (micro/caméra compris) SANS toucher à
  /// l'intention de voix ([_iAmReady]) ni au statut.
  Future<void> _resetPeer() async {
    _pendingCandidates.clear();
    _negotiationStarted = false;
    _pcFuture = null;
    final stream = _localStream;
    _localStream = null;
    for (final track in stream?.getTracks() ?? const []) {
      await track.stop();
    }
    await stream?.dispose();
    final videoStream = _localVideoStream;
    _localVideoStream = null;
    _localVideoTrack = null;
    _videoEnabled = false;
    for (final track in videoStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await videoStream?.dispose();
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    _remoteVideoActiveController.add(false);
    final pc = _pc;
    _pc = null;
    await pc?.close();
  }

  Future<void> _onOffer(Map<String, dynamic> payload) async {
    if (!_iAmReady) return;
    debugPrint(
      'VoiceCall: offre reçue, préparation de la réponse... '
      'payload.keys=${payload.keys} sdp.runtimeType=${payload['sdp'].runtimeType} '
      'sdp.length=${(payload['sdp'] as String?)?.length}',
    );
    try {
      await _ensurePeerConnection();
      await _pc!.setRemoteDescription(RTCSessionDescription(_decodeSdp(payload['sdp'] as String?), payload['type'] as String?));
      await _flushPendingCandidates();
      final answer = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(answer);
      debugPrint('VoiceCall: réponse créée, envoi...');
      await GameService.instance.sendVoiceSignal('answer', {'sdp': _encodeSdp(answer.sdp), 'type': answer.type});
    } catch (e, st) {
      debugPrint('VoiceCall: ÉCHEC traitement offre — $e\n$st');
      _setStatus(VoiceCallStatus.connecting);
      _scheduleReconnect(Duration.zero);
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> payload) async {
    if (_pc == null) return;
    await _pc!.setRemoteDescription(RTCSessionDescription(_decodeSdp(payload['sdp'] as String?), payload['type'] as String?));
    await _flushPendingCandidates();
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate'] as String?,
      payload['sdpMid'] as String?,
      payload['sdpMLineIndex'] as int?,
    );
    // Un candidat peut arriver avant l'offre (ou avant que notre connexion
    // existe) : on le garde de côté plutôt que de le perdre.
    if (_pc == null || await _pc!.getRemoteDescription() == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _pc!.addCandidate(candidate);
  }

  Future<void> _flushPendingCandidates() async {
    final pending = List<RTCIceCandidate>.of(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in pending) {
      await _pc?.addCandidate(candidate);
    }
  }

  // Le SDP transite en base64 (voir demande utilisateur, débogage :
  // "SessionDescription is NULL") — le middleware `TrimStrings` de Laravel
  // rogne les espaces/retours à la ligne en début/fin de CHAQUE chaîne de
  // la requête, y compris dans les champs imbriqués comme `payload.sdp` ;
  // or un SDP se termine conventionnellement par un retour à la ligne, que
  // le parseur SDP natif d'Android refuse une fois tronqué. Le base64 n'a
  // ni espace ni retour à la ligne en bordure, donc rien à rogner.
  static String? _encodeSdp(String? sdp) => sdp == null ? null : base64Encode(utf8.encode(sdp));

  static String? _decodeSdp(String? encoded) => encoded == null ? null : utf8.decode(base64Decode(encoded));

  Future<void> _teardown() async {
    _reconnectTimer?.cancel();
    _watchdog?.cancel();
    _negotiationStarted = false;
    _pcFuture = null;
    _pendingCandidates.clear();
    everConnected = false;
    final stream = _localStream;
    _localStream = null;
    for (final track in stream?.getTracks() ?? const []) {
      await track.stop();
    }
    await stream?.dispose();

    final videoStream = _localVideoStream;
    _localVideoStream = null;
    _localVideoTrack = null;
    _videoEnabled = false;
    for (final track in videoStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await videoStream?.dispose();
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    _remoteVideoActiveController.add(false);

    await _pc?.close();
    _pc = null;
    _setStatus(VoiceCallStatus.idle);
  }

  void _setStatus(VoiceCallStatus s) {
    if (_status == s) return;
    _status = s;
    _statusController.add(s);
  }
}
