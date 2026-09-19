import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:showcaseview/showcaseview.dart';

import 'core/app_router.dart';
import 'core/api_config.dart';
import 'core/app_update_checker.dart';
import 'core/pin_storage.dart';
import 'core/ritual_reminder_service.dart';
import 'features/box/box_scope.dart';
import 'features/home/app_shell.dart';
import 'features/lock/app_lock_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/shop/preferred_currency_notifier.dart';
import 'features/shop/subscription_status_notifier.dart';
import 'features/shop/wallet_balance_notifier.dart';
import 'core/push_notification_service.dart';
import 'firebase_options.dart';
import 'l10n/app_locale.dart';
import 'l10n/locale_controller.dart';
import 'l10n/locale_scope.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Une version publiée ne doit jamais partir sur localhost ni en HTTP.
  ApiConfig.assertSafeForRelease();
  // Sans ça, Android réserve une bande opaque blanche pour la barre de
  // navigation système en bas de l'écran plutôt que de laisser le contenu
  // de l'app (dégradé de thème) s'étendre derrière — visible en bas de tout
  // écran qui ne se termine pas déjà sur une couleur claire (voir
  // ThemedBackground, qui synchronise ensuite sa couleur/luminosité avec
  // le thème actif).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Uniquement Android pour l'instant (iOS reporté, voir DefaultFirebaseOptions) —
  // ne bloque jamais le démarrage de l'app si l'initialisation échoue.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await PushNotificationService.instance.createAndroidChannel();
  } catch (_) {}
  // Écoute BoxService dès maintenant — se resynchronisera dès qu'une Box
  // sera chargée (connexion, restauration de session...), y compris un
  // changement fait depuis l'autre appareil du couple.
  RitualReminderService.instance.start();
  // Peint le badge de solde instantanément dès le premier écran, avant même
  // qu'un appel réseau ait pu aboutir (voir WalletBalanceNotifier.refresh,
  // toujours appelé ensuite par les écrans concernés dès qu'il y a réseau).
  await WalletBalanceNotifier.instance.loadCached();
  // Idem pour le statut d'abonnement (voir CoinBalanceBadge) : sans ça, le
  // badge affichait d'abord le solde de pièces avant de basculer sur "∞"
  // dès que le serveur répondait — un flash visible constaté en réel (voir
  // demande utilisateur).
  await SubscriptionStatusNotifier.instance.loadCached();
  // Idem pour la devise de la Boutique (voir ShopScreen._ensureCurrencySelected)
  // : décider instantanément s'il faut proposer le choix, sans attendre le
  // réseau, qui laissait sinon les prix s'afficher un court instant avant.
  await PreferredCurrencyNotifier.instance.loadCached();
  // Guide pas-à-pas des jeux interactifs (voir GameGuideStorage/demande
  // utilisateur) — enregistré une seule fois ici, un singleton indépendant
  // du widget tree (voir ShowcaseView.get()), pour pouvoir enchaîner des
  // bulles à travers plusieurs écrans poussés (choix du mode → difficulté
  // → plateau) sans avoir à ré-enregistrer à chaque écran.
  // `disableBarrierInteraction: true` — sans ça, un tap accidentel en
  // dehors de la bulle (voir demande utilisateur : "si je clique dans un
  // espace vide le guide s'annule") fermait tout le guide d'un coup,
  // plutôt que de simplement l'ignorer ; il faut désormais taper la bulle
  // ou l'élément qu'elle désigne pour avancer. `globalTooltipActions` (voir
  // demande utilisateur : "comment on avance ? ajoute 2 btn... un pour
  // suivant... un pour fermer le guide") ajoute ces deux boutons, icône
  // seule, sur TOUTES les bulles de TOUS les guides de jeu.
  ShowcaseView.register(
    disableBarrierInteraction: true,
    globalTooltipActionConfig: const TooltipActionConfig(position: TooltipActionPosition.outside),
    globalTooltipActions: [
      TooltipActionButton(
        type: TooltipDefaultActionType.skip,
        name: '',
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        leadIcon: const ActionButtonIcon(icon: Icon(Icons.close_rounded, color: Colors.white, size: 18)),
      ),
      TooltipActionButton(
        type: TooltipDefaultActionType.next,
        name: '',
        leadIcon: const ActionButtonIcon(icon: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18)),
      ),
    ],
  );
  runApp(const BinomeApp());
}

class BinomeApp extends StatelessWidget {
  const BinomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Réécoute LocaleController pour que `locale:` (ci-dessous) suive un
    // changement de langue fait depuis les Paramètres sans redémarrer l'app
    // — sinon les widgets natifs Flutter (sélecteur d'heure/de date, menus
    // Cupertino...) restent bloqués sur la langue de démarrage, MaterialApp
    // n'étant construit qu'une fois. Nos propres écrans, eux, passent déjà
    // par LocaleScope (voir plus bas) et n'ont pas ce problème.
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) => MaterialApp(
        title: 'Binome',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.base,
        navigatorKey: AppRouter.navigatorKey,
        // Sans ça, les widgets Material/Cupertino natifs (showTimePicker,
        // showDatePicker, menus de sélection...) retombent sur l'anglais
        // par défaut, quelle que soit la langue choisie dans l'app — voir
        // AppLocale.all pour la liste des 12 langues supportées.
        locale: Locale(LocaleController.instance.current.code),
        supportedLocales: AppLocale.all.map((l) => Locale(l.code)),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Wrap le Navigator (pas juste `home`) pour que BoxScope/ThemeScope/
        // LocaleScope restent disponibles sur tous les écrans poussés
        // ensuite, pas seulement le premier — sinon un écran secondaire qui
        // lit ThemeScope.of()/LocaleScope.of() plante (voir l'incident
        // SlideDetailScreen/AppDrawer : InheritedWidget ne traverse pas vers
        // une route poussée si le scope n'entoure que le premier écran).
        // AppShell (barre de navigation globale) doit être le plus interne
        // des trois : elle a besoin de ThemeScope/LocaleScope pour se
        // dessiner.
        builder: (context, child) => BoxScope(child: ThemeScope(child: LocaleScope(child: AppShell(child: child!)))),
        home: const _AppGate(),
      ),
    );
  }
}

/// Porte d'entrée de l'app : si un code PIN a été défini (Paramètres), on
/// exige son saisie avant même de tenter de restaurer la session — sinon on
/// passe directement à [SplashScreen].
class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool? _locked;

  @override
  void initState() {
    super.initState();
    _checkLock();
    ThemeController.instance.load();
    LocaleController.instance.load();
    // Après le premier frame seulement : AppRouter.navigatorKey n'a pas
    // encore d'overlay attaché tant que MaterialApp n'a pas fini de
    // construire (nécessaire pour afficher la bannière/le dialogue de mise
    // à jour, voir AppUpdateChecker).
    WidgetsBinding.instance.addPostFrameCallback((_) => AppUpdateChecker.instance.checkAndPrompt());
  }

  Future<void> _checkLock() async {
    final enabled = await PinStorage.instance.isEnabled();
    if (mounted) setState(() => _locked = enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (_locked == null) {
      return const Scaffold(backgroundColor: AppColors.navy, body: SizedBox.shrink());
    }
    if (_locked == true) {
      return AppLockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return const SplashScreen();
  }
}
