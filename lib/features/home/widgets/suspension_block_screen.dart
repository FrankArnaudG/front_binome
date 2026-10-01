import 'package:flutter/material.dart';

import '../../../l10n/locale_scope.dart';

/// Plein écran affiché à un compte sanctionné pour avoir trop sollicité le
/// serveur (voir demande utilisateur : détection d'abus, blocage
/// automatique 24h/72h/indéfini). Message TOUJOURS identique, quel que soit
/// le palier — ne révèle jamais la durée (voir demande utilisateur : "sans
/// préciser le temps").
class SuspensionBlockScreen extends StatelessWidget {
  const SuspensionBlockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;

    return Material(
      color: const Color(0xFF1A1330),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top_rounded, color: Colors.white70, size: 64),
                const SizedBox(height: 24),
                Text(
                  t('suspension_block_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  t('suspension_block_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
