import 'package:flutter/material.dart';

import '../../../l10n/locale_scope.dart';

/// Bande persistante affichée aux comptes AUTORISÉS pendant une maintenance
/// active (voir demande utilisateur : "ces comptes doivent voir une bande
/// les informant que la maintenance est activée"). Non fermable — reste
/// visible tant que la maintenance l'est, pour ne jamais l'oublier.
class MaintenanceBanner extends StatelessWidget {
  const MaintenanceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;
    return Material(
      color: const Color(0xFFFFB300),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.build_circle_outlined, color: Colors.black87, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('maintenance_banner'),
                  style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
