import 'package:flutter/material.dart';

import '../models/send.dart';

/// Statut d'acheminement d'un message façon WhatsApp/Telegram — affiché
/// uniquement sur les bulles envoyées par la personne qui regarde l'écran
/// (jamais sur celles reçues) : un seul check (envoyé au serveur), deux
/// checks gris ("reçu" — voir DeliveryAckService côté Flutter/`Send.status
/// == 'delivered'`), deux checks bleus ("lu", voir SendSeen côté backend).
/// [sending]/[failed] sont des états purement locaux (envoi optimiste pas
/// encore confirmé par le serveur), sans équivalent en base.
enum SendTick { sending, sent, delivered, read, failed }

SendTick sendTickFor(Send send) => switch (send.status) {
      'seen' => SendTick.read,
      'delivered' => SendTick.delivered,
      _ => SendTick.sent,
    };

/// Coche(s) — un check gris (envoyé), deux checks gris (reçu), deux checks
/// bleus (lu), horloge (en cours) ou point d'alerte tapable pour réessayer
/// (échec d'un envoi optimiste encore local).
class SendTickIcon extends StatelessWidget {
  final SendTick tick;
  // Couleur de base pour "en cours"/"envoyé"/"reçu" — varie selon le fond
  // (texte blanc sur bulle en dégradé, ou couleur atténuée du thème en
  // dessous d'une carte-photo) ; "lu" et "échec" gardent leurs couleurs
  // fixes, volontairement voyantes quel que soit le fond.
  final Color color;
  final VoidCallback? onRetry;

  const SendTickIcon({super.key, required this.tick, required this.color, this.onRetry});

  @override
  Widget build(BuildContext context) {
    switch (tick) {
      case SendTick.sending:
        return SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: color));
      case SendTick.sent:
        return Icon(Icons.done_rounded, size: 14, color: color);
      case SendTick.delivered:
        return Icon(Icons.done_all_rounded, size: 14, color: color);
      case SendTick.read:
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.lightBlueAccent);
      case SendTick.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
        );
    }
  }
}
