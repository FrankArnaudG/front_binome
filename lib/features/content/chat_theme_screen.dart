import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/chat_theme.dart';
import '../../theme/chat_theme_controller.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';

/// "Thème de la discussion" (voir demande utilisateur, capture WhatsApp) —
/// grille de thèmes, le choix s'applique à TOUT le Carnet de bord (voir
/// ChatThemeController, strictement local à cet appareil). Pas de
/// personnalisation séparée bulle/fond (contrairement à WhatsApp) — chaque
/// thème est un pack complet, plus simple à parcourir et à prévisualiser.
class ChatThemeScreen extends StatefulWidget {
  const ChatThemeScreen({super.key});

  @override
  State<ChatThemeScreen> createState() => _ChatThemeScreenState();
}

class _ChatThemeScreenState extends State<ChatThemeScreen> {
  late ChatTheme _selected = ChatThemeController.instance.current;

  Future<void> _confirm() async {
    await ChatThemeController.instance.select(_selected);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          'Thème de la discussion',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Thèmes',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.62,
              children: [
                for (final chatTheme in ChatThemes.all)
                  _ThemeSwatch(
                    theme: theme,
                    chatTheme: chatTheme,
                    selected: _selected.id == chatTheme.id,
                    onTap: () => setState(() => _selected = chatTheme),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'La bulle de discussion et le fond d\'écran changeront pour tout le Carnet de bord. Seul·e toi peux voir ce thème.',
              style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackgroundMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.primary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _confirm,
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final ThemePalette theme;
  final ChatTheme chatTheme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch({
    required this.theme,
    required this.chatTheme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? theme.primary : Colors.transparent, width: 2.5),
                color: chatTheme.backgroundColor,
                image: chatTheme.backgroundAsset != null
                    ? DecorationImage(image: AssetImage(chatTheme.backgroundAsset!), fit: BoxFit.cover)
                    : null,
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 6,
                    right: 14,
                    top: 10,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(color: chatTheme.bubbleColor, borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            chatTheme.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted),
          ),
        ],
      ),
    );
  }
}
