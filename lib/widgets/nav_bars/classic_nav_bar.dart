import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import 'nav_item.dart';

/// Style 2 — barre classique pleine largeur : fond opaque ancré en bas de
/// l'écran (pas de flou/flottant), icône + label toujours visibles,
/// pastille arrondie derrière l'icône active (façon Material 3
/// NavigationBar). Le plus familier des 4 styles.
/// Prévu pour un `Scaffold(extendBody: false, ...)`.
class ClassicNavBar extends StatelessWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;

  const ClassicNavBar({super.key, required this.currentIndex, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = ThemeScope.paletteOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: (palette.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(items.length, (index) {
              return _ClassicButton(
                item: items[index],
                selected: index == currentIndex,
                palette: palette,
                onTap: () => onTap(index),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ClassicButton extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final ThemePalette palette;
  final VoidCallback onTap;

  const _ClassicButton({required this.item, required this.selected, required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: selected ? palette.primary.withValues(alpha: 0.14) : Colors.transparent,
                    ),
                    child: Icon(
                      selected ? item.filledIcon : item.outlinedIcon,
                      color: selected ? palette.primary : palette.textOnBackgroundMuted,
                      size: 22,
                    ),
                  ),
                  if ((item.badgeCount ?? 0) > 0)
                    Positioned(
                      top: -2,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          item.badgeCount! > 9 ? '9+' : '${item.badgeCount}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? palette.primary : palette.textOnBackgroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
