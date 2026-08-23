import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/profile_completion_screen.dart';
import '../features/box/box_choice_screen.dart';
import '../features/box/box_waiting_screen.dart';
import '../features/home/main_tab_screen.dart';
import '../features/home/tab_navigation_controller.dart';
import '../models/app_user.dart';
import '../models/box.dart';
import '../widgets/milestone_reminder_dialog.dart';
import '../widgets/notification_opt_in_prompt.dart';
import 'delivery_ack_service.dart';
import 'milestone_reminder_service.dart';
import 'push_notification_service.dart';

/// Centralise les transitions entre écrans plutôt que de répéter
/// `Navigator.push(MaterialPageRoute(...))` partout — en particulier la
/// logique "où aller après connexion/session", qui dépend maintenant du
/// statut de la Box et pas seulement de la session utilisateur.
class AppRouter {
  AppRouter._();

  /// Clé du Navigator racine — nécessaire pour naviguer (ex. revenir à
  /// [MainTabScreen] depuis un tap sur la barre globale, voir `AppShell`)
  /// depuis un contexte situé au-dessus du Navigator (celui de
  /// `MaterialApp.builder`), où `Navigator.of(context)` ne trouve rien.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Vrai une fois dans la zone authentifiée (Dashboard/Galerie/Jeux/Profil
  /// et tout ce qui s'ouvre depuis là) — c'est le signal que lit `AppShell`
  /// pour savoir s'il doit superposer la barre de navigation globale.
  /// Explicitement mis à jour ici plutôt que déduit du nom de la route :
  /// la plupart des écrans secondaires (Boutique, Poèmes-Slides...) sont
  /// poussés sans nom, donc un système basé sur les noms de route ne
  /// pourrait pas les distinguer des écrans pré-authentification.
  static final ValueNotifier<bool> showGlobalNavBar = ValueNotifier<bool>(false);

  /// Décide où envoyer l'utilisateur juste après authentification (Google)
  /// ou restauration de session, en fonction de l'état de sa Box.
  static void routeAfterAuth(BuildContext context, AppUser user, Box? box) {
    // Étape bloquante avant tout le reste (y compris avant de savoir si une
    // Box existe) : ni Google ni l'inscription classique ne collectent
    // genre/pays, et un compte Google peut arriver avec un nom fantaisiste
    // (voir AuthenticationController::loginWithGoogle côté backend).
    if (user.needsProfileCompletion) {
      toProfileCompletion(context, user, replace: true);
      return;
    }

    // Fire-and-forget : ne doit jamais bloquer/casser la navigation (voir
    // PushNotificationService, dégrade silencieusement si Firebase/permission
    // indisponible).
    _handlePushPermission();

    if (box == null || box.isDissolved) {
      toBoxChoice(context, user, replace: true);
    } else if (box.isWaiting) {
      toBoxWaiting(context, user, box, replace: true);
    } else {
      DeliveryAckService.instance.start(box.id, user.id);
      toHome(context, user, replace: true);
      // Les dates à cœur sont propres au couple : seulement pertinent une
      // fois dans une Box active (voir MilestoneReminderService).
      _handleMilestoneReminder();
    }
  }

  /// Affiche le rappel de date à cœur DANS l'app (voir
  /// showMilestoneReminderDialog) — canal indépendant de la permission de
  /// notification système, contrairement à _handlePushPermission ci-dessus.
  static Future<void> _handleMilestoneReminder() async {
    final message = await MilestoneReminderService.instance.checkAndNotify();
    if (message == null) return;

    // Laisse la navigation vers le Dashboard se poser avant de superposer
    // le rappel par-dessus (même raison que _handlePushPermission) — délai
    // légèrement plus long que ce dernier pour ne pas superposer les deux
    // modales si elles se déclenchent le même jour (rare : premier
    // lancement + jalon déjà dans la fenêtre des 30 jours).
    await Future.delayed(const Duration(milliseconds: 900));
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) await showMilestoneReminderDialog(ctx, message);
  }

  /// Avant de laisser l'OS trancher à froid dès le tout premier lancement,
  /// on montre notre propre sollicitation (voir [showNotificationOptInPrompt])
  /// UNIQUEMENT tant que la permission n'a encore jamais été demandée —
  /// une fois tranchée (accordée ou refusée), ce statut ne redevient jamais
  /// "non déterminé", donc ce chemin ne s'emprunte plus qu'une fois par
  /// installation. Si l'utilisateur ferme le prompt sans activer, on
  /// n'appelle PAS init() cette session : ça évite de déclencher la
  /// vraie demande système juste après un refus poli du nôtre — elle
  /// réapparaîtra simplement à la prochaine connexion (toujours "non
  /// déterminée" tant qu'on ne l'a pas explicitement demandée).
  static Future<void> _handlePushPermission() async {
    final status = await PushNotificationService.instance.currentAuthorizationStatus();
    if (status != AuthorizationStatus.notDetermined) {
      PushNotificationService.instance.init();
      return;
    }

    // Laisse la navigation qui suit (toBoxChoice/toHome/...) se poser avant
    // de superposer le prompt — sinon il s'afficherait sur l'écran qu'on
    // est en train de quitter plutôt que sur la destination.
    await Future.delayed(const Duration(milliseconds: 500));
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) await showNotificationOptInPrompt(ctx);
  }

  static void toProfileCompletion(BuildContext context, AppUser user, {bool replace = false}) {
    showGlobalNavBar.value = false;
    _go(context, MaterialPageRoute(builder: (_) => ProfileCompletionScreen(user: user)), replace);
  }

  static void toBoxChoice(BuildContext context, AppUser user, {bool replace = false}) {
    showGlobalNavBar.value = false;
    _go(context, MaterialPageRoute(builder: (_) => BoxChoiceScreen(user: user)), replace);
  }

  static void toBoxWaiting(BuildContext context, AppUser user, Box box, {bool replace = false}) {
    showGlobalNavBar.value = false;
    _go(context, MaterialPageRoute(builder: (_) => BoxWaitingScreen(user: user, box: box)), replace);
  }

  static void toHome(BuildContext context, AppUser user, {bool replace = false}) {
    showGlobalNavBar.value = true;
    TabNavigationController.instance.reset();
    _go(context, MaterialPageRoute(builder: (_) => MainTabScreen(user: user)), replace);
  }

  static void toLogin(BuildContext context) {
    showGlobalNavBar.value = false;
    TabNavigationController.instance.reset();
    _go(context, MaterialPageRoute(builder: (_) => const LoginScreen()), true);
  }

  static void _go(BuildContext context, MaterialPageRoute route, bool replace) {
    if (replace) {
      Navigator.of(context).pushAndRemoveUntil(route, (r) => false);
    } else {
      Navigator.of(context).push(route);
    }
  }
}
