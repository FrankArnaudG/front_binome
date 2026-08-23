import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
// `Config` existe aussi dans google_fonts (interne, sans rapport) — on
// masque le doublon plutôt que d'aliaser tout le paquet emoji_picker.
import 'package:google_fonts/google_fonts.dart' hide Config;

import '../l10n/locale_scope.dart';
import '../theme/theme_palette.dart';

/// Barre de composition façon messagerie (Telegram/WhatsApp) : pastille
/// émoji à gauche (bascule le clavier maison, voir [EmojiPickerPanel]),
/// aperçu du contenu au centre, bouton d'envoi rond à droite — pas de champ
/// texte, pas de pièce jointe, pas de micro. Partagée entre tous les
/// endroits de l'app où l'on compose UNIQUEMENT des émojis (jeu "Devine mon
/// émoji", réactions du Carnet de bord...).
class EmojiComposeBar extends StatelessWidget {
  final ThemePalette theme;
  final TextEditingController controller;
  final bool pickerOpen;
  final bool sending;
  final String placeholder;
  final VoidCallback onTapField;
  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;

  const EmojiComposeBar({
    super.key,
    required this.theme,
    required this.controller,
    required this.pickerOpen,
    required this.sending,
    this.placeholder = 'Compose en émojis…',
    required this.onTapField,
    required this.onToggleEmoji,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = controller.text.trim().isNotEmpty;
    final t = LocaleScope.of(context).t;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(28),
              // Bordure plus marquée qu'avant (0.25 -> 0.4) + une ombre
              // légère : sur un thème clair et plat (fond uni, sans scène
              // illustrée derrière), une bordure trop pâle rendait la barre
              // quasi invisible, fondue dans le fond.
              border: Border.all(color: theme.primary.withValues(alpha: pickerOpen ? 0.6 : 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onToggleEmoji,
                  icon: Icon(
                    pickerOpen ? Icons.emoji_emotions_rounded : Icons.emoji_emotions_outlined,
                    color: pickerOpen ? theme.primary : theme.textOnBackgroundMuted,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: onTapField,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: hasContent
                          ? Text(controller.text, style: const TextStyle(fontSize: 22), maxLines: 2, overflow: TextOverflow.ellipsis)
                          : Text(
                              placeholder,
                              style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
                            ),
                    ),
                  ),
                ),
                if (hasContent)
                  IconButton(
                    onPressed: controller.clear,
                    icon: Icon(Icons.close_rounded, size: 18, color: theme.textOnBackgroundMuted),
                    tooltip: t('common_clear'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendCircleButton(theme: theme, enabled: hasContent, sending: sending, onTap: onSend),
      ],
    );
  }
}

class _SendCircleButton extends StatelessWidget {
  final ThemePalette theme;
  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  const _SendCircleButton({required this.theme, required this.enabled, required this.sending, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Bordure visible à l'état désactivé (même fond que la barre autour
      // de lui, sans elle le cercle disparaît complètement sur un thème
      // clair et plat) — inutile une fois activé, le rose plein suffit.
      decoration: enabled
          ? null
          : BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primary.withValues(alpha: 0.4))),
      child: Material(
        color: enabled ? theme.primary : theme.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: (enabled && !sending) ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: sending
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: enabled ? Colors.white : theme.primary))
              // Pas de réduction d'alpha supplémentaire à l'état désactivé :
              // textOnBackgroundMuted est déjà atténué par rapport au texte
              // normal, l'assombrir encore le rendait à peine visible sur
              // un thème clair et plat.
              : Icon(Icons.send_rounded, size: 20, color: enabled ? Colors.white : theme.textOnBackgroundMuted),
          ),
        ),
      ),
    );
  }
}

/// Panneau du sélecteur d'émojis : en-tête avec recherche/fermeture, puis
/// la grille — sans la barre d'actions basse par défaut du paquet
/// (recherche + suppression), remplacée par cet en-tête et par un bouton
/// supprimer fixe en bas à droite de la grille. Entièrement rethemé pour
/// matcher la palette active (clair/sombre) plutôt que les couleurs par
/// défaut du paquet. Pas de bouton "Envoyer" ici : il vit en permanence
/// dans [EmojiComposeBar], juste au-dessus.
class EmojiPickerPanel extends StatefulWidget {
  final ThemePalette theme;
  final TextEditingController controller;
  final VoidCallback onClose;

  const EmojiPickerPanel({super.key, required this.theme, required this.controller, required this.onClose});

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  // Capturé depuis bottomActionBarConfig.customBottomActionBar (voir plus
  // bas) — c'est le seul moyen d'ouvrir la vue recherche du paquet
  // autrement que depuis sa barre basse par défaut qu'on masque ici.
  VoidCallback? _showSearchView;

  void _backspace() {
    final chars = widget.controller.text.characters;
    if (chars.isEmpty) return;
    widget.controller.text = chars.skipLast(1).toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final t = LocaleScope.of(context).t;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: theme.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, -6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _showSearchView?.call(),
                  icon: Icon(Icons.search_rounded, color: theme.textOnBackgroundMuted),
                  tooltip: t('emoji_search_tooltip'),
                  visualDensity: VisualDensity.compact,
                ),
                // Rappel discret centré entre les deux boutons : ce clavier
                // ne compose QUE des émojis (voir la doc d'EmojiComposeBar)
                // — sans lui, on pourrait croire à un clavier de texte
                // classique qui a juste changé d'apparence.
                Expanded(
                  child: Center(
                    child: Text(
                      t('emoji_only_hint'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 11.5, color: theme.textOnBackgroundMuted),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(Icons.keyboard_hide_rounded, color: theme.textOnBackgroundMuted),
                  tooltip: t('common_close'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Stack(
            children: [
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  textEditingController: widget.controller,
                  config: Config(
                    height: 250,
                    // Vérification Android-only (voir sa doc) passant par un
                    // canal de plateforme — sur les cibles où ce plugin natif
                    // tout juste ajouté n'est pas encore rebuild, elle peut
                    // faire échouer silencieusement le rendu (grille vide).
                    // Aucune perte fonctionnelle à la désactiver.
                    checkPlatformCompatibility: false,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: theme.surface,
                      columns: 8,
                      emojiSizeMax: 26,
                      buttonMode: ButtonMode.MATERIAL,
                      // De la place pour le bouton supprimer flottant, pour
                      // qu'il ne recouvre pas la dernière rangée d'émojis.
                      gridPadding: const EdgeInsets.only(bottom: 44),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: theme.surface,
                      indicatorColor: theme.primary,
                      iconColor: theme.textOnBackgroundMuted,
                      iconColorSelected: theme.primary,
                      dividerColor: Colors.transparent,
                      initCategory: Category.SMILEYS,
                      // Pas d'onglet "récents" : évite d'attendre
                      // SharedPreferences (encore un plugin natif tout neuf)
                      // au chargement, source d'un blocage silencieux le
                      // temps qu'il soit rebuild côté natif.
                      recentTabBehavior: RecentTabBehavior.NONE,
                    ),
                    // Barre basse par défaut (recherche + suppression)
                    // masquée : la recherche est remontée dans l'en-tête
                    // ci-dessus, la suppression devient le bouton fixe
                    // ci-dessous. On récupère juste le déclencheur de
                    // recherche du paquet au passage.
                    bottomActionBarConfig: BottomActionBarConfig(
                      customBottomActionBar: (config, state, showSearchView) {
                        _showSearchView = showSearchView;
                        return const SizedBox.shrink();
                      },
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: theme.surface,
                      buttonIconColor: theme.primary,
                      hintText: t('emoji_search_tooltip'),
                      hintTextStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                      inputTextStyle: GoogleFonts.nunito(color: theme.textOnBackground),
                    ),
                  ),
                ),
              ),
              // Position fixe (n'accompagne pas le défilement de la
              // grille), collée dans l'angle plutôt que flottante — fond
              // plein et opaque (theme.primary) pour ne jamais se fondre
              // avec la grille derrière.
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: theme.primary,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(14)),
                  child: InkWell(
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14)),
                    onTap: _backspace,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.backspace_rounded, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
