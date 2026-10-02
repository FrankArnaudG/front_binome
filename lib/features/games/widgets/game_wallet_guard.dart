import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/realtime_client.dart';
import '../../shop/shop_screen.dart';
import '../../shop/wallet_balance_notifier.dart';

/// Surveille le solde de tokens PARTAGÉ du couple pendant une partie de jeu
/// interactif en cours (voir BillGameSessions/GameEconomySetting côté
/// backend — "chaque minute qui passe équivaut à une petite portion de token
/// consommée", voir demande utilisateur) : affiche un avertissement discret
/// avant l'épuisement (voir [GameWalletLow]).
///
/// Le gel réel de la partie une fois le solde épuisé (voir demande
/// utilisateur : "même le jeu doit être coupé et non le micro et la caméra
/// seul") passe désormais par le mécanisme de PAUSE déjà existant — le
/// serveur pose lui-même la pause (voir BillGameSessions), le plateau se
/// fige donc automatiquement comme une pause normale, sans que ce widget
/// ait quoi que ce soit à faire pour ça. Ce widget se contente d'un message
/// informatif ponctuel au moment de l'épuisement, avec un raccourci vers la
/// boutique.
///
/// N'a d'effet QUE si [boxId] est fourni (mode à distance dans une Box) —
/// une partie en pass-and-play ou entre amis hors couple n'a pas de
/// portefeuille partagé à surveiller (voir demande utilisateur : "le
/// couple"), passer `null` alors désactive silencieusement ce widget.
class GameWalletGuard extends StatefulWidget {
  final String? boxId;
  final String sessionType;
  final String sessionId;

  const GameWalletGuard({
    super.key,
    required this.boxId,
    required this.sessionType,
    required this.sessionId,
  });

  @override
  State<GameWalletGuard> createState() => _GameWalletGuardState();
}

class _GameWalletGuardState extends State<GameWalletGuard> {
  bool _depletedNoticeShown = false;
  bool _warningShown = false;
  bool _criticalWarningShown = false;
  // Voir demande utilisateur : "après le 15 minutes, à 30 secondes avertir
  // aussi" — la facturation serveur (BillGameSessions) ne tourne qu'une fois
  // par minute, trop grossier pour viser pile 30 secondes restantes. On
  // reprogramme donc un minuteur LOCAL à chaque tick reçu (minutes_remaining
  // vient du serveur, mais le compte à rebours jusqu'à 30s est fait ici).
  Timer? _criticalTimer;

  @override
  void initState() {
    super.initState();
    final boxId = widget.boxId;
    if (boxId != null) {
      RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onEvent);
    }
  }

  @override
  void dispose() {
    final boxId = widget.boxId;
    if (boxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onEvent);
    }
    _criticalTimer?.cancel();
    super.dispose();
  }

  void _onEvent(RealtimeEvent event) {
    if (event.event == 'GameWalletTicked') {
      final rawBalance = event.data?['balance'];
      if (rawBalance != null) WalletBalanceNotifier.instance.set(WalletBalanceNotifier.parseBalance(rawBalance));
      return;
    }
    if (event.event == 'GameWalletLow') {
      final rawBalance = event.data?['balance'];
      if (rawBalance != null) WalletBalanceNotifier.instance.set(WalletBalanceNotifier.parseBalance(rawBalance));
      if (!mounted) return;
      final minutesRemaining = WalletBalanceNotifier.parseBalance(event.data?['minutes_remaining']);
      _scheduleCriticalWarning(minutesRemaining);
      if (_warningShown) return;
      _warningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Il reste environ ${minutesRemaining.round()} minute(s) de jeu — pensez à recharger.'),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    if (event.event == 'GameWalletDepleted') {
      final sessionId = event.data?['session_id'] as String?;
      // Uniquement CETTE partie précise — voir demande utilisateur : une autre partie en cours en
      // parallèle avec le même solde commun continue tant qu'ELLE a de quoi être facturée.
      if (sessionId != widget.sessionId || _depletedNoticeShown || !mounted) return;
      _criticalTimer?.cancel();
      _depletedNoticeShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Solde de tokens épuisé — la partie est en pause.'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Recharger',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen())),
          ),
        ),
      );
    }
  }

  /// Reprogrammé à CHAQUE tick `GameWalletLow` (voir doc du champ) — un
  /// tick plus récent remplace toujours le précédent, pour coller à la
  /// dernière estimation serveur plutôt qu'à une extrapolation qui dérive.
  void _scheduleCriticalWarning(double minutesRemaining) {
    if (_criticalWarningShown) return;
    _criticalTimer?.cancel();
    final secondsUntilCritical = (minutesRemaining * 60) - 30;
    if (secondsUntilCritical <= 0) {
      _showCriticalWarning();
      return;
    }
    _criticalTimer = Timer(Duration(seconds: secondsUntilCritical.round()), _showCriticalWarning);
  }

  void _showCriticalWarning() {
    if (_criticalWarningShown || _depletedNoticeShown || !mounted) return;
    _criticalWarningShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Il reste environ 30 secondes de jeu — recharge vite !'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
