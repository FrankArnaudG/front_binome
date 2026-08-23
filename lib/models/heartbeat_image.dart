import 'package:flutter/material.dart';

/// Une image d'un battement de cœur avec son point focal — réglé côté admin
/// (voir HeartbeatMessageController), snapshotté au moment de l'envoi
/// (HeartbeatNudge.images côté backend). [focalX]/[focalY] sont en
/// pourcentage (0-100, 50/50 = centre) ; [alignment] les convertit dans le
/// repère Flutter (-1..1) attendu par Image.network(alignment: ...).
class HeartbeatImage {
  final String url;
  final double focalX;
  final double focalY;

  const HeartbeatImage({
    required this.url,
    this.focalX = 50,
    this.focalY = 50,
  });

  Alignment get alignment => Alignment(
        (focalX / 100) * 2 - 1,
        (focalY / 100) * 2 - 1,
      );

  factory HeartbeatImage.fromJson(Map<String, dynamic> json) => HeartbeatImage(
        url: json['url'] as String,
        focalX: (json['focal_x'] as num?)?.toDouble() ?? 50,
        focalY: (json['focal_y'] as num?)?.toDouble() ?? 50,
      );
}
