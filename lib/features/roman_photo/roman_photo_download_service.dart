import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'roman_photo_local_db.dart';
import 'roman_photo_story.dart';

/// Télécharge les pages d'UN tome et les enregistre dans la base SQLite
/// locale (voir RomanPhotoLocalDb) — jamais comme fichiers séparés (voir
/// demande utilisateur). Un seul téléchargement à la fois par tome ;
/// [progressFor] expose une progression 0.0-1.0 pendant le téléchargement,
/// `null` en dehors (ni commencé, ni en cours) — l'état "déjà téléchargé"
/// se lit séparément depuis RomanPhotoLocalDb.isDownloaded, pas depuis ce
/// notifier.
class RomanPhotoDownloadService {
  RomanPhotoDownloadService._();
  static final RomanPhotoDownloadService instance = RomanPhotoDownloadService._();

  final Map<String, ValueNotifier<double?>> _progress = {};

  ValueNotifier<double?> progressFor(String volumeId) => _progress.putIfAbsent(volumeId, () => ValueNotifier(null));

  bool isDownloading(String volumeId) => progressFor(volumeId).value != null;

  /// Télécharge page par page (séquentiel, pas en parallèle) — un tome de
  /// roman-photo compte peu de pages, la simplicité prime sur la vitesse ici,
  /// et ça borne naturellement la RAM utilisée en même temps (voir demande
  /// utilisateur sur la consommation mémoire).
  Future<void> download(RomanPhotoVolume volume, String storyId) async {
    if (isDownloading(volume.id)) return;
    final notifier = progressFor(volume.id);
    final total = volume.pageAssets.length;
    notifier.value = 0;

    try {
      for (var i = 0; i < total; i++) {
        final response = await http.get(Uri.parse(volume.pageAssets[i]));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode} pour la page ${i + 1}');
        }
        await RomanPhotoLocalDb.instance.savePage(volume.id, i, response.bodyBytes);
        notifier.value = (i + 1) / total;
      }
      await RomanPhotoLocalDb.instance.markComplete(volume.id, storyId, total);
    } catch (e) {
      // Échec en cours de route : retire les pages déjà partiellement
      // enregistrées plutôt que de laisser un tome à moitié téléchargé —
      // isDownloaded() doit rester franc (tout ou rien).
      await RomanPhotoLocalDb.instance.deleteVolume(volume.id);
      rethrow;
    } finally {
      notifier.value = null;
    }
  }
}
