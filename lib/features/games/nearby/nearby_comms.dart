import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:nearby_connections/nearby_connections.dart';
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

/// Canal de communication (texte ET voix) multiplexé sur la MÊME connexion
/// Nearby que celle utilisée par le transport du jeu (voir
/// *_transport_nearby.dart de chaque jeu) — chaque message du jeu a déjà un
/// champ "type" ('init'/'state'/'flip'/...), ce canal ajoute simplement
/// 'text_message'/'voice_chunk' sans jamais toucher au protocole du jeu
/// lui-même. [handleIncoming] doit être appelé AVANT
/// `transport.onPayloadReceived` (voir *_nearby_connect_screen.dart) : il
/// consomme les messages de ce canal et laisse passer tout le reste
/// inchangé.
///
/// Voix : PCM16 mono 16kHz brut capturé au micro (voir [startTalking]),
/// envoyé en petits paquets façon talkie-walkie — contrairement au mode à
/// distance (voir VoiceCallService), jamais de WebRTC ni de serveur de
/// signalisation : uniquement le canal Bluetooth/Wifi Direct déjà utilisé
/// par le jeu (voir demande utilisateur). Encodé en base64 à l'intérieur
/// du même JSON que les autres messages, pour rester sur un seul protocole
/// simple plutôt que de mélanger JSON et paquets binaires bruts sur le même
/// canal (voir *_transport_nearby.dart : un payload non-JSON y ferait
/// planter le `jsonDecode` du jeu).
class NearbyComms {
  final Nearby nearby;
  final String endpointId;
  final _messagesController = StreamController<NearbyChatMessage>.broadcast();
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSubscription;
  bool _talking = false;
  bool _playbackReady = false;

  static const _sampleRate = 16000;

  NearbyComms({required this.nearby, required this.endpointId});

  Stream<NearbyChatMessage> get messages => _messagesController.stream;

  bool get isTalking => _talking;

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

  /// Retourne `true` si ce canal a consommé le payload (chat texte ou
  /// paquet vocal) — l'appelant doit alors s'arrêter là. Retourne `false`
  /// pour tout le reste (messages du jeu), à transmettre au transport du
  /// jeu comme avant.
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
      default:
        return false;
    }
  }

  void dispose() {
    _messagesController.close();
    unawaited(stopTalking());
    unawaited(_recorder.dispose());
    if (_playbackReady) unawaited(FlutterPcmSound.release());
  }
}
