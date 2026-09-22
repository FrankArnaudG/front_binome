import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:image/image.dart' as img;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Un message de chat texte échangé en direct entre les deux téléphones en
/// mode "présentiel connecté" (voir demande utilisateur : pouvoir
/// communiquer sans serveur, sans base de données, sans connexion
/// internet — uniquement via Bluetooth/Wifi Direct comme le jeu
/// lui-même).
class NearbyChatMessage {
  final String text;
  final bool fromMe;

  const NearbyChatMessage({required this.text, required this.fromMe});
}

/// Canal de communication (texte, voix ET vidéo) multiplexé sur la MÊME
/// connexion Nearby que celle utilisée par le transport du jeu (voir
/// *_transport_nearby.dart de chaque jeu) — chaque message du jeu a déjà un
/// champ "type" ('init'/'state'/'flip'/...), ce canal ajoute simplement
/// 'text_message'/'voice_chunk'/'video_frame' sans jamais toucher au
/// protocole du jeu lui-même. [handleIncoming] doit être appelé AVANT
/// `transport.onPayloadReceived` (voir *_nearby_connect_screen.dart) : il
/// consomme les messages de ce canal et laisse passer tout le reste
/// inchangé.
///
/// Voix : PCM16 mono 16kHz brut capturé au micro (voir [startTalking]),
/// envoyé en petits paquets façon talkie-walkie. Vidéo : images JPEG basse
/// résolution/fréquence capturées caméra (voir [startVideo]) — contrairement
/// au mode à distance (voir VoiceCallService), jamais de WebRTC ni de
/// serveur de signalisation : uniquement le canal Bluetooth/Wifi Direct
/// déjà utilisé par le jeu (voir demande utilisateur). Tout est encodé en
/// base64 à l'intérieur du même JSON que les autres messages, pour rester
/// sur un seul protocole simple plutôt que de mélanger JSON et paquets
/// binaires bruts sur le même canal (voir *_transport_nearby.dart : un
/// payload non-JSON y ferait planter le `jsonDecode` du jeu).
class NearbyComms {
  final Nearby nearby;
  final String endpointId;
  final _messagesController = StreamController<NearbyChatMessage>.broadcast();
  // `null` signale l'arrêt de la vidéo côté distant (voir _onVideoStop) —
  // sans cette distinction, la dernière image reçue restait affichée
  // indéfiniment après que le binôme/ami ait coupé sa caméra (voir demande
  // utilisateur : "j'ai fermé les deux caméras mais celui-ci est resté
  // bloqué, il ne disparaît pas").
  final _remoteVideoFrameController = StreamController<Uint8List?>.broadcast();
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSubscription;
  bool _talking = false;
  bool _playbackReady = false;
  cam.CameraController? _cameraController;
  bool _sendingVideo = false;
  bool _encodingFrame = false;
  // Diagnostic (voir demande utilisateur : "si j'active ma vidéo ça n'apparaît pas chez mon
  // binôme") — compte les images réellement envoyées, pour distinguer dans les journaux "rien n'est
  // envoyé" de "envoyé mais jamais reçu/affiché en face".
  int _framesSent = 0;
  // Même diagnostic côté réception, pour distinguer "jamais envoyé" de
  // "envoyé mais jamais reçu" dans les journaux du binôme/ami.
  int _framesReceived = 0;

  static const _sampleRate = 16000;
  // Qualité JPEG volontairement basse (voir demande utilisateur : "es-ce
  // possible sans internet") — priorité à la fluidité/bande passante sur
  // Bluetooth/Wifi Direct plutôt qu'à la netteté de l'image.
  static const _jpegQuality = 35;

  NearbyComms({required this.nearby, required this.endpointId});

  Stream<NearbyChatMessage> get messages => _messagesController.stream;
  Stream<Uint8List?> get remoteVideoFrames => _remoteVideoFrameController.stream;

  bool get isTalking => _talking;
  bool get isSendingVideo => _sendingVideo;
  cam.CameraController? get cameraController => _cameraController;

  void sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    nearby.sendBytesPayload(
      endpointId,
      Uint8List.fromList(utf8.encode(jsonEncode({'type': 'text_message', 'text': trimmed}))),
    );
    _messagesController.add(NearbyChatMessage(text: trimmed, fromMe: true));
  }

  /// Démarre la capture micro — chaque paquet audio capturé est envoyé
  /// immédiatement (voir [_sendVoiceChunk]), aucune mise en mémoire tampon
  /// longue (voir demande utilisateur : "maintenir pour parler", même
  /// principe push-to-talk que VoiceCallOverlay). Retourne `false` si la
  /// permission micro est refusée.
  Future<bool> startTalking() async {
    if (_talking) return true;
    try {
      if (!await _recorder.hasPermission()) return false;
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sampleRate, numChannels: 1),
      );
      _talking = true;
      _micSubscription = stream.listen(_sendVoiceChunk);
      return true;
    } catch (_) {
      _talking = false;
      return false;
    }
  }

  Future<void> stopTalking() async {
    if (!_talking) return;
    _talking = false;
    await _micSubscription?.cancel();
    _micSubscription = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Best-effort — l'enregistrement est de toute façon coupé côté micro.
    }
  }

  void _sendVoiceChunk(Uint8List pcm16Bytes) {
    if (pcm16Bytes.isEmpty) return;
    nearby.sendBytesPayload(
      endpointId,
      Uint8List.fromList(utf8.encode(jsonEncode({'type': 'voice_chunk', 'pcm16': base64Encode(pcm16Bytes)}))),
    );
  }

  Future<void> _ensurePlaybackReady() async {
    if (_playbackReady) return;
    await FlutterPcmSound.setup(sampleRate: _sampleRate, channelCount: 1);
    _playbackReady = true;
  }

  Future<void> _playIncomingVoice(Uint8List pcm16Bytes) async {
    await _ensurePlaybackReady();
    final samples = pcm16Bytes.buffer.asInt16List(pcm16Bytes.offsetInBytes, pcm16Bytes.lengthInBytes ~/ 2);
    await FlutterPcmSound.feed(PcmArrayInt16.fromList(samples));
  }

  /// Démarre la capture caméra (résolution basse, voir
  /// [cam.ResolutionPreset.low]) — une image sur deux/trois seulement est
  /// réellement encodée+envoyée (voir [_encodingFrame], sert de
  /// contre-pression naturelle : si l'encodage JPEG précédent n'est pas
  /// fini, l'image suivante est simplement sautée plutôt que mise en
  /// attente). Retourne `false` si la permission caméra est refusée ou
  /// qu'aucune caméra n'est disponible.
  Future<bool> startVideo() async {
    if (_sendingVideo) return true;
    try {
      if (!(await Permission.camera.request()).isGranted) {
        debugPrint('NearbyComms: caméra refusée par les réglages du téléphone');
        return false;
      }
      final cameras = await cam.availableCameras();
      if (cameras.isEmpty) {
        debugPrint('NearbyComms: aucune caméra disponible sur ce téléphone');
        return false;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = cam.CameraController(
        camera,
        cam.ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: cam.ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _cameraController = controller;
      _sendingVideo = true;
      _framesSent = 0;
      await controller.startImageStream(_onCameraFrame);
      debugPrint('NearbyComms: capture caméra démarrée (${camera.lensDirection})');
      return true;
    } catch (e) {
      debugPrint('NearbyComms: échec du démarrage de la caméra — $e');
      _sendingVideo = false;
      final controller = _cameraController;
      _cameraController = null;
      unawaited(controller?.dispose());
      return false;
    }
  }

  Future<void> stopVideo() async {
    if (!_sendingVideo) return;
    _sendingVideo = false;
    // Prévient le binôme/ami que la vidéo s'arrête, pour qu'il efface la
    // dernière image reçue plutôt que de la laisser figée à l'écran (voir
    // _onVideoStop côté réception).
    nearby.sendBytesPayload(
      endpointId,
      Uint8List.fromList(utf8.encode(jsonEncode({'type': 'video_stop'}))),
    );
    final controller = _cameraController;
    _cameraController = null;
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller?.dispose();
    } catch (_) {
      // Best-effort — la capture est de toute façon marquée arrêtée.
    }
  }

  void _onCameraFrame(cam.CameraImage frame) {
    if (!_sendingVideo || _encodingFrame) return;
    _encodingFrame = true;
    unawaited(_encodeAndSendFrame(frame).whenComplete(() => _encodingFrame = false));
  }

  Future<void> _encodeAndSendFrame(cam.CameraImage frame) async {
    try {
      final image = _yuv420ToImage(frame);
      final jpg = img.encodeJpg(image, quality: _jpegQuality);
      nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(jsonEncode({'type': 'video_frame', 'jpg': base64Encode(jpg)}))),
      );
      _framesSent++;
      // Une fois au démarrage puis de loin en loin (jamais à chaque image, ça inonderait les
      // journaux) — voir demande utilisateur : diagnostiquer "envoyé mais jamais reçu en face".
      if (_framesSent == 1 || _framesSent % 30 == 0) {
        debugPrint('NearbyComms: image vidéo envoyée #$_framesSent (${jpg.length} octets)');
      }
    } catch (e) {
      debugPrint('NearbyComms: échec de l\'envoi de l\'image vidéo #${_framesSent + 1} — $e');
      // Best-effort : une image ratée n'interrompt pas le flux, la
      // suivante arrivera au tour d'après.
    }
  }

  /// Conversion YUV_420_888 (Android, 3 plans semi-planaires Y/U/V, voir
  /// demande utilisateur : Nearby Connections est de toute façon
  /// Android-only dans cette app) vers une image RGB — algorithme standard
  /// BT.601, aucune dépendance à un encodeur matériel/plateforme.
  img.Image _yuv420ToImage(cam.CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    final image = img.Image(width: width, height: height, numChannels: 3);

    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final yRow = y * yRowStride;
      final uvRow = (y >> 1) * uvRowStride;
      for (int x = 0; x < width; x++) {
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        final yValue = yPlane.bytes[yRow + x];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];

        final r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round().clamp(0, 255);
        final b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  }

  /// Retourne `true` si ce canal a consommé le payload (chat texte, paquet
  /// vocal ou image vidéo) — l'appelant doit alors s'arrêter là. Retourne
  /// `false` pour tout le reste (messages du jeu), à transmettre au
  /// transport du jeu comme avant.
  bool handleIncoming(Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return false;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    switch (message['type']) {
      case 'text_message':
        final text = message['text'] as String?;
        if (text != null && text.trim().isNotEmpty) {
          _messagesController.add(NearbyChatMessage(text: text, fromMe: false));
        }
        return true;
      case 'voice_chunk':
        final b64 = message['pcm16'] as String?;
        if (b64 != null) {
          try {
            unawaited(_playIncomingVoice(base64Decode(b64)));
          } catch (_) {
            // Paquet corrompu/incomplet — ignoré, sans interrompre l'appel.
          }
        }
        return true;
      case 'video_frame':
        final b64 = message['jpg'] as String?;
        if (b64 != null) {
          try {
            _framesReceived++;
            if (_framesReceived == 1 || _framesReceived % 30 == 0) {
              debugPrint('NearbyComms: image vidéo reçue #$_framesReceived (${b64.length} caractères b64)');
            }
            _remoteVideoFrameController.add(base64Decode(b64));
          } catch (_) {
            // Image corrompue/incomplète — ignorée, la suivante arrivera.
          }
        }
        return true;
      case 'video_stop':
        // Le binôme/ami a coupé sa caméra — efface la dernière image reçue
        // au lieu de la laisser figée à l'écran (voir demande utilisateur).
        _remoteVideoFrameController.add(null);
        return true;
      default:
        return false;
    }
  }

  void dispose() {
    _messagesController.close();
    _remoteVideoFrameController.close();
    unawaited(stopTalking());
    unawaited(stopVideo());
    unawaited(_recorder.dispose());
    if (_playbackReady) unawaited(FlutterPcmSound.release());
    // Sans ceci, la connexion Bluetooth/Wifi Direct restait active côté
    // natif après avoir quitté la partie (voir demande utilisateur : "si je
    // veux me reconnecter à un autre jeu ou au même jeu, la recherche pour
    // rejoindre ne donne rien" — seul un redémarrage complet de l'app
    // libérait la connexion coincée). Un `Nearby()` recréé côté Dart à
    // l'écran de connexion suivant ne change rien : côté natif la connexion
    // aux points de terminaison est un état global, pas lié à l'instance
    // Dart.
    unawaited(nearby.stopAllEndpoints());
  }
}
