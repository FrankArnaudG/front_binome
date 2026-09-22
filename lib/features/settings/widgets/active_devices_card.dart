import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/push_notification_service.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';

/// Appareils sur lesquels le compte est connecté, et « Déconnecter les autres appareils » (voir
/// demande utilisateur) : l'appareil qu'on tient en main n'est JAMAIS déconnecté ici. Avec un seul
/// appareil, le bouton affiche simplement une information.
class ActiveDevicesCard extends StatefulWidget {
  const ActiveDevicesCard({super.key});

  @override
  State<ActiveDevicesCard> createState() => _ActiveDevicesCardState();
}

class _DeviceSession {
  final bool current;
  final DateTime? lastUsedAt;

  const _DeviceSession({required this.current, required this.lastUsedAt});

  factory _DeviceSession.fromJson(Map<String, dynamic> json) => _DeviceSession(
        current: json['current'] == true,
        lastUsedAt: DateTime.tryParse((json['last_used_at'] ?? json['created_at'] ?? '') as String)?.toLocal(),
      );
}

class _ActiveDevicesCardState extends State<ActiveDevicesCard> {
  List<_DeviceSession>? _sessions;
  bool _loadFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/auth/sessions') as Map<String, dynamic>;
      final sessions = (data['sessions'] as List).map((e) => _DeviceSession.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  String _ago(DateTime? date) {
    if (date == null) return 'activité inconnue';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 2) return "actif à l'instant";
    if (diff.inMinutes < 60) return 'actif il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'actif il y a ${diff.inHours} h';
    return 'actif il y a ${diff.inDays} j';
  }

  Future<void> _logoutOthers() async {
    final sessions = _sessions;
    if (sessions == null || _busy) return;

    if (sessions.length <= 1) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Un seul téléphone'),
          content: const Text("Ce compte n'est ouvert que sur ce téléphone : il n'y a aucun autre appareil à déconnecter."),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }

    final others = sessions.length - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnecter les autres appareils ?'),
        content: Text(
          others == 1
              ? "L'autre appareil sera déconnecté et devra se reconnecter. Ce téléphone reste connecté."
              : 'Les $others autres appareils seront déconnectés et devront se reconnecter. Ce téléphone reste connecté.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Déconnecter', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    String message;
    try {
      final pushToken = await PushNotificationService.instance.currentToken();
      await ApiClient.instance.post('/auth/sessions/logout-others', body: {if (pushToken != null) 'device_token': pushToken});
      message = others == 1 ? 'Autre appareil déconnecté.' : '$others autres appareils déconnectés.';
      await _load();
    } catch (_) {
      message = 'Impossible de déconnecter les autres appareils. Réessaie dans un instant.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final sessions = _sessions;

    final String summary;
    if (sessions != null) {
      summary = sessions.length <= 1
          ? "Ton compte n'est ouvert que sur ce téléphone."
          : 'Ton compte est ouvert sur ${sessions.length} téléphones.';
    } else {
      summary = _loadFailed ? 'Impossible de charger les appareils connectés.' : 'Chargement…';
    }

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appareils connectés',
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 4),
          Text(summary, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
          if (sessions != null && sessions.length > 1) ...[
            const SizedBox(height: 10),
            for (final (index, session) in sessions.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.smartphone_rounded, size: 18, color: session.current ? theme.primary : theme.textOnBackgroundMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session.current ? 'Ce téléphone' : 'Autre téléphone ${index + 1}',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: session.current ? FontWeight.w800 : FontWeight.w600,
                          color: theme.textOnBackground,
                        ),
                      ),
                    ),
                    Text(_ago(session.lastUsedAt), style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: (sessions == null || _busy) ? null : _logoutOthers,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.devices_other_rounded, size: 18),
              label: const Text('Déconnecter les autres appareils'),
            ),
          ),
        ],
      ),
    );
  }
}
