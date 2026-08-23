import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';

class DangerZoneCard extends StatelessWidget {
  final bool showLeaveBox;
  final VoidCallback onLeaveBox;
  final VoidCallback onDeleteAccount;

  const DangerZoneCard({
    super.key,
    required this.showLeaveBox,
    required this.onLeaveBox,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (showLeaveBox) ...[
            _DangerTile(
              icon: Icons.heart_broken_rounded,
              label: t('danger_leave_partner'),
              color: error,
              onTap: onLeaveBox,
            ),
            Divider(height: 1, color: theme.textOnBackgroundMuted.withValues(alpha: 0.2)),
          ],
          _DangerTile(
            icon: Icons.delete_forever_rounded,
            label: t('danger_delete_account'),
            color: error,
            onTap: onDeleteAccount,
          ),
        ],
      ),
    );
  }
}

class _DangerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DangerTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      onTap: onTap,
    );
  }
}
