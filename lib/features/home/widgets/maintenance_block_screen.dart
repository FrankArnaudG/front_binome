import 'package:flutter/material.dart';

import '../../../core/maintenance_service.dart';
import '../../../l10n/locale_scope.dart';

/// Plein écran affiché à un compte NON autorisé pendant une maintenance
/// active — remplace tout le reste (voir AppShell.build) pour que le compte
/// ne puisse plus solliciter le serveur (voir demande utilisateur : "ils ne
/// doivent pas pouvoir solliciter trop le serveur"). L'heure de fin, si
/// réglée, est toujours affichée en GMT (voir demande utilisateur : "si y'a
/// l'heure préciser que c'est l'heure GMT").
class MaintenanceBlockScreen extends StatelessWidget {
  const MaintenanceBlockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;
    final service = MaintenanceService.instance;
    final endsAt = service.endsAt;

    return Material(
      color: const Color(0xFF1A1330),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.build_circle_outlined, color: Colors.white70, size: 64),
                const SizedBox(height: 24),
                Text(
                  t('maintenance_block_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  (service.message?.trim().isNotEmpty ?? false) ? service.message!.trim() : t('maintenance_block_default_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                ),
                if (endsAt != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    t('maintenance_block_ends_at', {'time': _formatGmt(endsAt)}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatGmt(DateTime dt) {
    final utc = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(utc.day)}/${two(utc.month)} ${two(utc.hour)}:${two(utc.minute)}';
  }
}
