import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import 'heartbeat_card.dart';
import 'heartbeat_family_picker.dart';

/// Compose un battement de cœur personnalisé — texte + image de famille
/// OBLIGATOIRE (voir demande utilisateur : "l'association d'image est
/// obligatoire"), avec une étape de prévisualisation avant l'envoi réel
/// ("on peut prévisualiser avant d'envoyer, on clique sur prévisualiser et
/// dans ça on a envoyer"). UNE seule implémentation partagée par les 4
/// endroits de l'app qui composent un battement de cœur personnalisé —
/// Dashboard (DarkQuickActionsGrid), Carnet de bord (TimelineScreen),
/// réponse à une pensée (SlideDetailScreen) et réponse à une carte-question
/// de jeu (GameBoxHistoryScreen) — voir demande utilisateur : "partout dans
/// l'app où y'a battement de cœur doit être mis à jour", pour ne plus
/// dupliquer ce dialogue à quatre endroits différents.
///
/// Retourne `null` si annulé, sinon le message ET la famille choisie (jamais
/// nulle à ce stade — le bouton "Prévisualiser" reste désactivé tant
/// qu'aucune n'est choisie).
Future<({String message, String family})?> showHeartbeatComposeDialog(
  BuildContext context, {
  required String? senderGender,
}) {
  return showDialog<({String message, String family})>(
    context: context,
    builder: (_) => HeartbeatComposeDialog(senderGender: senderGender),
  );
}

class HeartbeatComposeDialog extends StatefulWidget {
  final String? senderGender;

  const HeartbeatComposeDialog({super.key, required this.senderGender});

  @override
  State<HeartbeatComposeDialog> createState() => _HeartbeatComposeDialogState();
}

class _HeartbeatComposeDialogState extends State<HeartbeatComposeDialog> {
  final _controller = TextEditingController();
  String? _selectedFamily;
  bool _previewing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        _previewing ? t('heartbeat_preview_title') : t('heartbeat_compose_title'),
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
      ),
      content: _previewing ? _buildPreview(theme) : _buildCompose(theme, t),
      actions: _previewing ? _previewActions(theme, t) : _composeActions(theme, t),
    );
  }

  Widget _buildCompose(ThemePalette theme, String Function(String, [Map<String, String>?]) t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 140,
          maxLines: 3,
          style: GoogleFonts.nunito(color: theme.textOnBackground),
          cursorColor: theme.primary,
          // Recalcule l'activation du bouton "Prévisualiser" à chaque
          // frappe (voir _composeActions, canPreview exige un texte ET une
          // famille non vides).
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('heartbeat_compose_hint'),
            hintStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          t('heartbeat_family_picker_label'),
          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 6),
        HeartbeatFamilyPicker(
          theme: theme,
          senderGender: widget.senderGender,
          selected: _selectedFamily,
          onSelect: (family) => setState(() => _selectedFamily = family),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemePalette theme) {
    return SizedBox(
      width: 250,
      child: AspectRatio(
        // Portrait 4:5, même proportion que les images de famille (voir
        // HeartbeatCard.usesFamilyImage) — la carte réellement envoyée aura
        // ce même cadrage.
        aspectRatio: 4 / 5,
        child: HeartbeatCard(
          images: const [],
          message: _controller.text.trim(),
          theme: theme,
          family: _selectedFamily,
          senderGender: widget.senderGender,
        ),
      ),
    );
  }

  List<Widget> _composeActions(ThemePalette theme, String Function(String, [Map<String, String>?]) t) {
    final canPreview = _controller.text.trim().isNotEmpty && _selectedFamily != null;
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t('common_cancel'), style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: theme.primary),
        onPressed: canPreview ? () => setState(() => _previewing = true) : null,
        child: Text(t('heartbeat_preview_button')),
      ),
    ];
  }

  List<Widget> _previewActions(ThemePalette theme, String Function(String, [Map<String, String>?]) t) {
    return [
      TextButton(
        onPressed: () => setState(() => _previewing = false),
        child: Text(t('heartbeat_preview_edit_button'), style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: theme.primary),
        onPressed: () => Navigator.of(context).pop((message: _controller.text.trim(), family: _selectedFamily!)),
        child: Text(t('heartbeat_send_button')),
      ),
    ];
  }
}
