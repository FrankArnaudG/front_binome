import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/theme_palette.dart';

/// Un raccourci replié derrière le bouton "+" d'une barre de composition
/// (voir [ComposerActionsTrigger]/[ComposerActionsDrawer]). [child] est déjà
/// le bouton rond complet (Material+InkWell+contenu) — la liste change
/// selon l'écran (poème/battement de cœur seuls pour une réaction, +
/// "envoyer une autre carte" dans un fil de jeu), mais chaque bouton garde
/// la liberté de son propre habillage (icône simple, dégradé, loader...).
class ComposerAction {
  final String tooltip;
  final Widget child;

  const ComposerAction({required this.tooltip, required this.child});

  /// Raccourci le plus courant : icône simple sur pastille `theme.surface`,
  /// avec un loader en repli quand [loading] est vrai (voir la réponse par
  /// battement de cœur, dont l'appel réseau peut prendre un instant).
  factory ComposerAction.icon({
    required String tooltip,
    required IconData icon,
    required ThemePalette theme,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return ComposerAction(
      tooltip: tooltip,
      child: Material(
        color: theme.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: loading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary))
                : Icon(icon, size: 20, color: theme.primary),
          ),
        ),
      ),
    );
  }
}

/// Bouton "+" (devient "×" par rotation à l'ouverture) placé à gauche d'un
/// champ de saisie — un seul bouton, quel que soit le nombre de raccourcis
/// repliés derrière lui (voir [ComposerActionsDrawer], juste au-dessus).
/// Partagé entre SlideDetailScreen (réagir à un poème reçu) et
/// GameCardThreadScreen (répondre à une carte-question) : les deux avaient
/// chacun leur propre copie de ce bouton avant, désormais une seule source
/// pour que le geste (et son animation) reste identique partout où l'app
/// propose des raccourcis repliables, et pour qu'un futur changement de
/// style n'ait qu'un seul endroit à modifier.
class ComposerActionsTrigger extends StatelessWidget {
  final ThemePalette theme;
  final bool open;
  final VoidCallback onTap;

  const ComposerActionsTrigger({super.key, required this.theme, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.add_rounded, size: 22, color: theme.primary),
          ),
        ),
      ),
    );
  }
}

/// Tiroir de raccourcis déployé au-dessus du champ de saisie (voir
/// [ComposerActionsTrigger]) — la liste passée par l'appelant définit quels
/// raccourcis apparaissent pour CE type de discussion, sans dupliquer le
/// rendu (alignement, espacement, tooltip) d'un écran à l'autre.
class ComposerActionsDrawer extends StatelessWidget {
  final List<ComposerAction> actions;

  const ComposerActionsDrawer({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Tooltip(message: actions[i].tooltip, child: actions[i].child),
        ],
      ],
    );
  }
}

/// Une ligne (icône + libellé + chevron) d'une feuille de raccourcis "+"
/// façon Carnet de bord (voir TimelineScreen._openComposeMenu) — partagée
/// pour que tout écran proposant une feuille "+" en liste (plutôt qu'un
/// tiroir d'icônes, voir [ComposerActionsDrawer]) garde le même rendu.
class ComposeMenuTile extends StatelessWidget {
  final ThemePalette theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ComposeMenuTile({super.key, required this.theme, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: theme.primary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w600, color: theme.textOnBackground),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
