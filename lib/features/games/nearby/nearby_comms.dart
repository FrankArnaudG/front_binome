import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

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

/// Canal de communication texte multiplexé sur la MÊME connexion Nearby
/// que celle utilisée par le transport du jeu (voir *_transport_nearby.dart
/// de chaque jeu) — chaque message du jeu a déjà un champ "type"
/// ('init'/'state'/'flip'/...), ce canal ajoute simplement 'text_message'
/// sans jamais toucher au protocole du jeu lui-même. [handleIncoming] doit
/// être appelé AVANT `transport.onPayloadReceived` (voir
/// *_nearby_connect_screen.dart) : il consomme les messages de chat et
/// laisse passer tout le reste inchangé.
class NearbyComms {
  final Nearby nearby;
  final String endpointId;
  final _messagesController = StreamController<NearbyChatMessage>.broadcast();

  NearbyComms({required this.nearby, required this.endpointId});

  Stream<NearbyChatMessage> get messages => _messagesController.stream;

  void sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    nearby.sendBytesPayload(
      endpointId,
      Uint8List.fromList(utf8.encode(jsonEncode({'type': 'text_message', 'text': trimmed}))),
    );
    _messagesController.add(NearbyChatMessage(text: trimmed, fromMe: true));
  }

  /// Retourne `true` si ce canal a consommé le payload (message de chat) —
  /// l'appelant doit alors s'arrêter là. Retourne `false` pour tout le
  /// reste (messages du jeu), à transmettre au transport du jeu comme
  /// avant.
  bool handleIncoming(Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return false;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    if (message['type'] != 'text_message') return false;
    final text = message['text'] as String?;
    if (text != null && text.trim().isNotEmpty) {
      _messagesController.add(NearbyChatMessage(text: text, fromMe: false));
    }
    return true;
  }

  void dispose() {
    _messagesController.close();
  }
}
