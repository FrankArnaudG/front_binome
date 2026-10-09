import 'dart:math';
import 'dart:typed_data';

/// Génère un UUIDv7 côté client (horodatage sur les 48 bits de poids fort,
/// reste aléatoire) — même format que `Str::orderedUuid()` côté Laravel
/// (voir Send::HasUuids), pour qu'un id généré ici reste triable
/// chronologiquement au même titre qu'un id généré serveur. Utilisé pour
/// pouvoir citer un message avant même que le serveur ait confirmé son
/// envoi (voir GameCardThreadScreen._PendingText.localId).
String generateUuid7() {
  final rand = Random.secure();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final bytes = Uint8List(16);
  bytes[0] = (ts >> 40) & 0xff;
  bytes[1] = (ts >> 32) & 0xff;
  bytes[2] = (ts >> 24) & 0xff;
  bytes[3] = (ts >> 16) & 0xff;
  bytes[4] = (ts >> 8) & 0xff;
  bytes[5] = ts & 0xff;
  for (var i = 6; i < 16; i++) {
    bytes[i] = rand.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}
