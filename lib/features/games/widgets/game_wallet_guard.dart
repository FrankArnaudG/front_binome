import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/realtime_client.dart';
import '../../../theme/theme_scope.dart';
import '../../shop/shop_screen.dart';
import '../../shop/wallet_balance_notifier.dart';

/// Surveille le solde de pièces PARTAGÉ du couple pendant une partie de jeu
/// interactif en cours (voir BillGameSessions/GameEconomySetting côté
/// backend — "chaque minute qui passe équivaut à une petite portion de coin
/// consommée", voir demande utilisateur) : affiche un avertissement discret
/// avant l'épuisement (voir [GameWalletLow]), puis un popup bloquant
/// "recharger ou terminer la partie" dès que le solde tombe à zéro (voir
/// [GameWalletDepleted]) — le micro/la caméra en cours (voir
/// VoiceCallOverlay.forceEnded) sont coupés automatiquement à ce moment,
/// jamais avant.
///
/// N'a d'effet QUE si [boxId] est fourni (mode à distance dans une Box) —
/// une partie en pass-and-play ou entre amis hors couple n'a pas de
/// portefeuille partagé à surveiller (voir demande utilisateur : "le
/// couple"), passer `null` alors désactive silencieusement ce widget.
class GameWalletGuard extends StatefulWidget {
  final String? boxId;
  final String sessionType;
  final String sessionId;
  // Le couple vient d'épuiser son solde EN COURS de cette partie précise —
  // voir demande utilisateur : "le micro et la vidéo sont coupés
  // automatiquement" (voir VoiceCallOverlay.forceEnded, wiré par l'appelant).
  final ValueChanged<bool>? onDepletedChanged;
  // Termine la partie EN COURS (voir widget.transport.abandon() côté
  // appelant, même geste qu'un abandon volontaire) — bouton "Terminer la
  // partie" du popup.
  final VoidCallback onEndGame;

  const GameWalletGuard({
    super.key,
    required this.boxId,
    required this.sessionType,
    required this.sessionId,
    required this.onEndGame,
    this.onDepletedChanged,
  });

  @override
  State<GameWalletGuard> createState() => _GameWalletGuardState();
}

class _GameWalletGuardState extends State<GameWalletGuard> {
  bool _dialogShown = false;
  bool _warningShown = false;

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
      if (_warningShown || !mounted) return;
      _warningShown = true;
      final minutes = WalletBalanceNotifier.parseBalance(event.data?['minutes_remaining']).round();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Il reste environ $minutes minute(s) de jeu — pensez à recharger.'),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    if (event.event == 'GameWalletDepleted') {
      final sessionId = event.data?['session_id'] as String?;
      if (sessionId != widget.sessionId || _dialogShown || !mounted) return;
      _dialogShown = true;
      widget.onDepletedChanged?.call(true);
      _showDepletedDialog();
    }
  }

  Future<void> _showDepletedDialog() async {
    final theme = ThemeScope.paletteOf(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text('Solde de pièces épuisé', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
        content: Text(
          "Votre couple n'a plus de pièces pour continuer cette partie. Rechargez pour poursuivre, ou terminez la partie ici.",
          style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.onEndGame();
            },
            child: const Text('Terminer la partie', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()));
            },
            child: Text('Recharger', style: TextStyle(color: theme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
