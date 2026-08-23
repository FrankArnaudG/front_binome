import 'package:shared_preferences/shared_preferences.dart';

import '../features/box/box_service.dart';
import '../l10n/locale_controller.dart';
import '../models/box_milestone.dart';

/// Rappel "dès la connexion" pour une date à cœur qui approche (voir
/// couple_profile_screen.dart pour la gestion des jalons eux-mêmes) —
/// n'apparaît qu'aux paliers J-14/J-7/J-2/J-1/jour-J, jamais entre les deux
/// (voir checkAndNotify) : sans cette restriction, tout jour d'ouverture
/// dans la fenêtre de 30 jours redéclenchait le rappel générique, alors
/// même que son texte promettait de ne prévenir qu'à ces paliers précis.
/// Le dédoublonnage se fait par "palier le plus urgent déjà annoncé", pas
/// par jour civil exact — sans ça, quelqu'un qui rate pile le jour J-14
/// (connecté à J-23, puis seulement à J-10) ne verrait jamais aucun
/// rappel pour cette occurrence : à la prochaine connexion, le palier
/// manqué est rattrapé plutôt que perdu.
///
/// Uniquement affiché DANS l'app (voir AppRouter._handleMilestoneReminder
/// + showMilestoneReminderDialog) — pas de notification système : elle
/// nécessiterait un envoi programmé côté serveur (indépendant des ouvertures
/// d'app) pour être fiable app fermée, ce qui n'existe pas ; déclenchée
/// seulement à l'ouverture comme avant, elle ferait doublon avec la boîte
/// de dialogue qui s'affiche au même moment.
class MilestoneReminderService {
  MilestoneReminderService._();
  static final MilestoneReminderService instance = MilestoneReminderService._();

  // Doit couvrir le plus large des paliers filtrés dans checkAndNotify
  // (J-14) — inutile d'aller plus loin, aucun palier au-delà n'est retenu.
  static const _windowDays = 14;

  /// Prochaine occurrence de [date] à partir d'aujourd'hui — recurrence
  /// annuelle sur mois/jour, même logique que
  /// _MilestonesSectionState._nextOccurrence côté CoupleProfileScreen.
  DateTime _nextOccurrence(DateTime date, DateTime today) {
    var next = DateTime(today.year, date.month, date.day);
    if (next.isBefore(today)) next = DateTime(today.year + 1, date.month, date.day);
    return next;
  }

  /// Appelé uniquement pour un palier connu (voir checkAndNotify) — le
  /// premier d'entre eux atteint (J-14) porte aussi l'annonce des suivants,
  /// pour que l'app n'ait jamais besoin de le redire chaque jour. Traduit
  /// via [LocaleController.instance] directement (pas de BuildContext ici,
  /// ce service tourne avant que l'écran de destination soit posé — voir
  /// AppRouter._handleMilestoneReminder).
  String _messageFor(int daysUntil, String label) {
    final t = LocaleController.instance.t;
    final params = {'label': label};
    switch (daysUntil) {
      case 0:
        return t('milestone_reminder_today', params);
      case 1:
        return t('milestone_reminder_tomorrow', params);
      case 2:
        return t('milestone_reminder_2days', params);
      case 7:
        return t('milestone_reminder_week', params);
      default:
        return t('milestone_reminder_2weeks', params);
    }
  }

  /// À appeler à chaque connexion/ouverture de l'app (voir
  /// AppRouter.routeAfterAuth), une fois qu'on sait que l'utilisateur
  /// appartient à une Box active — les jalons sont propres au couple, pas
  /// à un compte hors Box. Renvoie le message à afficher dans l'app, ou
  /// `null` s'il n'y a rien à montrer aujourd'hui.
  Future<String?> checkAndNotify() async {
    try {
      final milestones = await BoxService.instance.fetchMilestones();
      if (milestones.isEmpty) return null;

      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final prefs = await SharedPreferences.getInstance();

      // Le plus proche d'abord : si plusieurs jalons tombent dans la
      // fenêtre, un seul rappel par ouverture d'app suffit — pas la peine
      // de saturer l'utilisateur de notifications d'un coup.
      final upcoming = milestones
          .map((m) => (milestone: m, next: _nextOccurrence(m.date, todayOnly)))
          .where((e) => e.next.difference(todayOnly).inDays <= _windowDays)
          .toList()
        ..sort((a, b) => a.next.compareTo(b.next));
      if (upcoming.isEmpty) return null;

      final nearest = upcoming.first;
      final daysUntil = nearest.next.difference(todayOnly).inDays;

      // Le palier le plus URGENT (le plus proche du jour J) déjà atteint
      // mais pas encore annoncé — pas une correspondance exacte sur
      // `daysUntil`, pour rattraper un palier manqué (voir doc de la
      // classe) plutôt que le perdre définitivement.
      const thresholds = [0, 1, 2, 7, 14]; // du plus urgent au plus lointain
      final reached = thresholds.where((t) => daysUntil <= t);
      if (reached.isEmpty) return null;
      final threshold = reached.reduce((a, b) => a < b ? a : b);

      final lastKey = _lastThresholdKey(nearest.milestone, nearest.next);
      final lastNotified = prefs.getInt(lastKey) ?? thresholds.last + 1;
      if (threshold >= lastNotified) return null;

      final message = _messageFor(threshold, nearest.milestone.label);
      await prefs.setInt(lastKey, threshold);

      return message;
    } catch (_) {
      // best effort — jamais bloquant pour la connexion.
      return null;
    }
  }

  /// Une clé par occurrence annuelle du jalon (pas par jour civil) — porte
  /// le dernier palier annoncé, remise à zéro naturellement l'année
  /// suivante puisque [nextOccurrence] change d'année.
  String _lastThresholdKey(BoxMilestone milestone, DateTime nextOccurrence) =>
      'milestone_reminder_threshold_${milestone.id}_${nextOccurrence.year}';
}
