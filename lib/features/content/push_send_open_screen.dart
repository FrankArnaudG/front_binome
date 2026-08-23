import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/send.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'content_service.dart';
import 'slide_detail_screen.dart';

/// Écran de transition affiché immédiatement au tap d'une notification push
/// (voir PushNotificationService), le temps de charger l'envoi visé — pour
/// que l'app s'ouvre tout de suite plutôt que de rester figée sur l'écran
/// précédent en attendant la requête. Se remplace lui-même par
/// [SlideDetailScreen] dès que le Send arrive, ou revient au Carnet de bord
/// si l'envoi est introuvable (supprimé, etc.).
class PushSendOpenScreen extends StatefulWidget {
  final String sendId;
  final AppUser user;

  const PushSendOpenScreen({super.key, required this.sendId, required this.user});

  @override
  State<PushSendOpenScreen> createState() => _PushSendOpenScreenState();
}

class _PushSendOpenScreenState extends State<PushSendOpenScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Send? send;
    try {
      send = await ContentService.instance.fetchSend(widget.sendId);
    } catch (_) {
      send = null;
    }
    if (!mounted) return;

    if (send == null) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SlideDetailScreen(
          send: send!,
          isMine: send.senderId == widget.user.id,
          user: widget.user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Scaffold(
      backgroundColor: theme.background,
      body: ThemedBackground(
        child: Center(child: CircularProgressIndicator(color: theme.primary)),
      ),
    );
  }
}
