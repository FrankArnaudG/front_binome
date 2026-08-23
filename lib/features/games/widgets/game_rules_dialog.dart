import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/game.dart';
import '../../../theme/theme_scope.dart';

/// Pop-up "Comment jouer" — accessible depuis la liste des jeux (icône
/// ampoule sur la carte, voir _CardBack dans games_menu_screen) pour
/// consulter les règles avant même d'entrer dans le jeu. Contenu piloté par
/// game.rules, entièrement éditable — mise en forme comprise — depuis
/// l'espace admin. Mini-syntaxe volontairement minimale plutôt qu'un vrai
/// éditeur riche (aucune dépendance supplémentaire) : ligne vide = nouveau
/// paragraphe, "- " en début de ligne = puce, "1. " en début de ligne =
/// liste numérotée, **mot** = gras.
void showGameRulesDialog(BuildContext context, Game game) {
  final rules = game.rulesFor(LocaleScope.of(context).current.code);
  if (rules == null || rules.trim().isEmpty) return;
  showDialog<void>(context: context, builder: (dialogContext) => _GameRulesDialog(game: game, rules: rules));
}

class _GameRulesDialog extends StatelessWidget {
  final Game game;
  final String rules;

  const _GameRulesDialog({required this.game, required this.rules});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final locale = LocaleScope.of(context);
    final t = locale.t;
    final textStyle = GoogleFonts.nunito(fontSize: 13, height: 1.5, color: theme.textOnBackgroundMuted);
    final boldStyle = textStyle.copyWith(fontWeight: FontWeight.w800, color: theme.textOnBackground);
    final blocks = _parseRuleBlocks(rules, textStyle, boldStyle);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        // Règles parfois longues (voir la liste d'exemples de "Devine mon
        // émoji") : sans cette limite + le Scrollbar plus bas, le contenu
        // débordait carrément de l'écran au lieu de défiler.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_rounded, color: theme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('game_rules_title'),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: theme.textOnBackground),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(game.nameFor(locale.current.code), style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
              const SizedBox(height: 16),
              Flexible(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < blocks.length; i++) ...[
                          blocks[i],
                          if (i < blocks.length - 1) const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: theme.primary),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('common_understood')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final RegExp _numberedLinePattern = RegExp(r'^(\d+)\.\s+(.*)$');

List<Widget> _parseRuleBlocks(String rules, TextStyle style, TextStyle boldStyle) {
  final paragraphs = rules.trim().split(RegExp(r'\n\s*\n'));
  return paragraphs.map((paragraph) {
    final lines = paragraph.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final isBulletList = lines.isNotEmpty && lines.every((l) => l.trimLeft().startsWith('- '));

    if (isBulletList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: style),
                    Expanded(child: _richText(line.trimLeft().substring(2), style, boldStyle)),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    final numberedMatches = lines.map((l) => _numberedLinePattern.firstMatch(l.trimLeft())).toList();
    final isNumberedList = numberedMatches.isNotEmpty && numberedMatches.every((m) => m != null);
    if (isNumberedList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: numberedMatches
            .map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${match!.group(1)}.', style: style),
                    ),
                    Expanded(child: _richText(match.group(2)!, style, boldStyle)),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    return _richText(lines.join(' '), style, boldStyle);
  }).toList();
}

Widget _richText(String text, TextStyle style, TextStyle boldStyle) {
  final spans = <InlineSpan>[];
  final boldPattern = RegExp(r'\*\*(.+?)\*\*');
  var cursor = 0;
  for (final match in boldPattern.allMatches(text)) {
    if (match.start > cursor) spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
    spans.add(TextSpan(text: match.group(1), style: boldStyle));
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor), style: style));
  return RichText(text: TextSpan(children: spans));
}
