import 'dart:io';

import '../../core/api_client.dart';
import '../../models/box_sound.dart';

/// Appels API pour les sons partagés du couple (voir BoxSoundController) —
/// même esprit que PhotoVaultService.
class SharedSoundsService {
  SharedSoundsService._();
  static final SharedSoundsService instance = SharedSoundsService._();

  static const maxSounds = 5;

  Future<List<BoxSound>> fetchSounds() async {
    final data = await ApiClient.instance.get('/boxes/sounds') as List;
    return data.map((e) => BoxSound.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BoxSound> uploadSound(File file) async {
    final data = await ApiClient.instance.postMultipart(
      '/boxes/sounds',
      fieldName: 'sound',
      file: file,
    ) as Map<String, dynamic>;
    return BoxSound.fromJson(data);
  }

  Future<void> deleteSound(String soundId) async {
    await ApiClient.instance.delete('/boxes/sounds/$soundId');
  }

  /// Diffuse le son en direct sur le canal de la Box (voir SoundPlayed côté
  /// backend) — ne fait rien de visible si le binôme n'a pas l'app ouverte,
  /// c'est le comportement voulu (pas de notification de repli).
  Future<void> playSound(String soundId) async {
    await ApiClient.instance.post('/boxes/sounds/$soundId/play');
  }
}
