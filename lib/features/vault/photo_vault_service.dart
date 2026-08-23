import 'dart:io';

import '../../core/api_client.dart';
import '../../models/box_photo.dart';

/// Appels API pour le "Jardin secret" (voir BoxPhotoController) — même
/// esprit que BoxService/ShopService : pas d'état partagé ici, chaque écran
/// recharge la liste au besoin.
class PhotoVaultService {
  PhotoVaultService._();
  static final PhotoVaultService instance = PhotoVaultService._();

  static const maxPhotos = 100;

  Future<List<BoxPhoto>> fetchPhotos() async {
    final data = await ApiClient.instance.get('/boxes/photos') as List;
    return data.map((e) => BoxPhoto.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// La recompression (redimensionnement + réencodage JPEG qualité 75) se
  /// fait côté serveur (voir BoxPhotoController::compress) — le fichier
  /// original part tel quel, seul le résultat stocké est allégé.
  Future<BoxPhoto> uploadPhoto(File file) async {
    final data = await ApiClient.instance.postMultipart(
      '/boxes/photos',
      fieldName: 'photo',
      file: file,
    ) as Map<String, dynamic>;
    return BoxPhoto.fromJson(data);
  }

  Future<void> deletePhoto(String photoId) async {
    await ApiClient.instance.delete('/boxes/photos/$photoId');
  }

  /// À appeler quand la photo s'ouvre en plein écran (voir PhotoViewerScreen),
  /// jamais juste pour une miniature affichée dans la grille — le serveur
  /// retire le fichier de son disque dès que les deux membres de la Box
  /// l'ont "vue" ainsi (voir BoxPhotoController::markViewed) ; l'app doit
  /// donc l'avoir déjà mis en cache local (CachedNetworkImage) à ce moment,
  /// seule copie restante ensuite. Best-effort : un échec réseau ici ne
  /// doit jamais bloquer l'affichage de la photo déjà chargée à l'écran.
  Future<void> markViewed(String photoId) async {
    try {
      await ApiClient.instance.post('/boxes/photos/$photoId/viewed');
    } catch (_) {
      // best effort
    }
  }

  /// Bouton affiché quand une photo a expiré côté serveur avant d'avoir été
  /// ouverte (voir ExpireBoxPhotos) — pas de renvoi automatique possible, le
  /// fichier original n'existe plus nulle part : juste une notification
  /// push pour prévenir qui a envoyé (voir BoxPhotoController::requestResend).
  Future<void> requestResend(String photoId) async {
    await ApiClient.instance.post('/boxes/photos/$photoId/request-resend');
  }
}
