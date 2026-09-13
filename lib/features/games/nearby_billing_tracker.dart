import '../../core/local_cache.dart';
import '../../core/server_clock.dart';
import 'game_service.dart';

/// Suivi local des jours de jeu "présentiel connecté" (Nearby Connections,
/// voir demande utilisateur) — ce mode fonctionne SANS internet pendant la
/// partie, donc aucun contact serveur n'est possible en direct. Chaque
/// appareil marque localement les jours joués (stockage persistant normal,
/// PAS le dossier cache — survit à un redémarrage ou un vidage de cache,
/// voir LocalCache), puis les déclare au serveur dès qu'une connexion
/// revient (voir NearbyBillingController::report côté backend, forfait
/// journalier).
///
/// Namespacé par Box (voir demande utilisateur : deux comptes sur le même
/// appareil ne doivent jamais mélanger leur suivi) — jamais une clé globale
/// au téléphone.
class NearbyBillingTracker {
  NearbyBillingTracker._();
  static final NearbyBillingTracker instance = NearbyBillingTracker._();

  String _key(String boxId) => 'nearby_pending_days_$boxId';

  String _dateString(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<List<String>> _readPending(String boxId) async {
    final data = await LocalCache.instance.readJson<List<dynamic>>(_key(boxId));
    return data?.map((e) => e.toString()).toList() ?? <String>[];
  }

  /// Marque AUJOURD'HUI (selon l'horloge recalée sur le serveur, voir
  /// ServerClock — jamais l'horloge brute de l'appareil) comme joué pour
  /// cette Box — appelé dès qu'une partie Nearby démarre réellement (voir
  /// les 7 transports Nearby). Idempotent : rejouer plusieurs parties le
  /// même jour n'ajoute qu'UNE seule entrée.
  Future<void> markPlayedToday(String boxId) async {
    final today = _dateString(ServerClock.instance.now());
    final pending = await _readPending(boxId);
    if (pending.contains(today)) return;
    await LocalCache.instance.writeJson(_key(boxId), [...pending, today]);
  }

  /// Tente de déclarer les jours en attente au serveur — best-effort,
  /// jamais bloquant (voir demande utilisateur : "premier arrivé,
  /// facturé", pas d'attente). Ne vide les données locales QUE si le
  /// serveur confirme avoir bien reçu la déclaration (voir demande
  /// utilisateur : "s'assurer que la déclaration est faite" avant de
  /// vider) — sinon elles restent en attente pour la prochaine tentative.
  Future<void> reportAndClear(String boxId) async {
    final pending = await _readPending(boxId);
    if (pending.isEmpty) return;
    try {
      await GameService.instance.reportNearbyDays(pending);
      await LocalCache.instance.writeJson(_key(boxId), <String>[]);
    } catch (_) {
      // Best-effort — pas de connexion ou erreur serveur : on retentera
      // au prochain déclenchement (résumé de l'app, fin de partie...),
      // les jours en attente restent intacts en local.
    }
  }
}
