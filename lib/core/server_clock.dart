import 'dart:io';

/// Horloge corrigée par rapport au serveur — voir ApiClient._decode, qui
/// alimente cet écart à CHAQUE réponse HTTP (en-tête `Date`, présent sur
/// toute requête, rien à ajouter côté backend). À utiliser PARTOUT où un
/// calcul de temps écoulé compare une horodate serveur (ex. `started_at`
/// d'une partie) à "maintenant" (ex. `_elapsed()` des 7 jeux interactifs),
/// plutôt que `DateTime.now()` brut : une horloge d'appareil désynchronisée
/// (constaté en réel — deux téléphones affichant un temps de partie
/// totalement différent pour la MÊME partie) fausse sinon complètement
/// l'affichage, sans que rien ne soit réellement cassé côté serveur.
class ServerClock {
  ServerClock._();
  static final ServerClock instance = ServerClock._();

  Duration _offset = Duration.zero;

  /// "Maintenant", recalé sur l'horloge du serveur.
  DateTime now() => DateTime.now().toUtc().add(_offset);

  /// Appelé à chaque réponse API (voir ApiClient) — recalcule l'écart à
  /// chaque fois plutôt qu'une seule fois au lancement, pour rester correct
  /// même si l'horloge de l'appareil dérive en cours de session (constaté
  /// en réel sur un émulateur qui reprend après une longue veille).
  void updateFromHeader(String? dateHeader) {
    if (dateHeader == null) return;
    try {
      final serverTime = HttpDate.parse(dateHeader);
      _offset = serverTime.difference(DateTime.now().toUtc());
    } catch (_) {
      // En-tête absent/mal formé : on garde le dernier écart connu plutôt
      // que de retomber brutalement sur l'horloge brute de l'appareil.
    }
  }
}
