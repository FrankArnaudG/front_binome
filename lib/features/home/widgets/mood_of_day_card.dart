import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/mood.dart';
import '../../../theme/theme_scope.dart';

/// "Notre Humeur du Jour" (voir demande utilisateur) — résumé compact sur le
/// Dashboard, avec la petite illustration de l'humeur postée ; le choix se
/// fait sur un écran dédié (voir MoodScreen, ouvert via [onTap]).
class MoodOfDayCard extends StatelessWidget {
  final Mood? mine;
  final Mood? partner;
  final String? myName;
  final String? myGender;
  final String? partnerGender;
  final String? partnerName;
  final VoidCallback onTap;
  final VoidCallback? onTapPartner;

  const MoodOfDayCard({
    super.key,
    required this.mine,
    required this.partner,
    required this.myName,
    required this.myGender,
    required this.partnerGender,
    required this.partnerName,
    required this.onTap,
    this.onTapPartner,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('mood_card_title'),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('mood_card_prompt'),
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  color: theme.textOnBackgroundMuted,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: onTap,
                          child: mine != null
                              ? _MoodThumb(
                                  imagePath: moodAssetPath(
                                    mine!.moodKey,
                                    myGender,
                                  ),
                                  editLabel: t('mood_edit_cta'),
                                )
                              : _MoodPromptTile(
                                  theme: theme,
                                  label: t('mood_save_cta'),
                                ),
                        ),
                        if (myName != null)
                          Positioned(
                            top: -10,
                            right: -10,
                            child: _NameBadge(name: myName!, theme: theme),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        partner != null
                            ? GestureDetector(
                                onTap: onTapPartner,
                                child: _MoodThumb(
                                  imagePath: moodAssetPath(
                                    partner!.moodKey,
                                    partnerGender,
                                  ),
                                  editLabel: null,
                                ),
                              )
                            : _MoodWaitingTile(
                                theme: theme,
                                label: partnerName != null
                                    ? '${t('mood_card_waiting_prefix')} $partnerName…'
                                    : t('mood_card_waiting'),
                              ),
                        if (partnerName != null)
                          Positioned(
                            top: -10,
                            right: -10,
                            child: _NameBadge(name: partnerName!, theme: theme),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pastille avec le prénom, débordant du coin supérieur droit de la tuile
/// (voir demande utilisateur) — indique à qui appartient chaque humeur.
class _NameBadge extends StatelessWidget {
  final String name;
  final dynamic theme;

  const _NameBadge({required this.name, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Largeur plafonnée (voir demande utilisateur : un prénom trop long
      // ne doit pas déborder sur les autres éléments) — le Text tronque
      // avec des points de suspension une fois cette limite atteinte.
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.surface, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: GoogleFonts.nunito(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MoodThumb extends StatelessWidget {
  final String imagePath;
  final String? editLabel;

  const _MoodThumb({required this.imagePath, required this.editLabel});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1.2,
            // BoxFit.contain (voir MoodScreen, même correctif) — les images
            // n'ont pas toutes le même ratio d'origine, "cover" coupait donc
            // certaines de façon inégale selon leur composition.
            child: Container(
              color: theme.surface,
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
        ),
        if (editLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            editLabel!,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ma tuile quand je n'ai pas encore posté aujourd'hui — CTA vers MoodScreen.
class _MoodPromptTile extends StatelessWidget {
  final dynamic theme;
  final String label;

  const _MoodPromptTile({required this.theme, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
      ),
      child: AspectRatio(
        aspectRatio: 1.2,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💭', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodWaitingTile extends StatelessWidget {
  final dynamic theme;
  final String label;

  const _MoodWaitingTile({required this.theme, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: AspectRatio(
        aspectRatio: 1.2,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⏳', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: theme.textOnBackgroundMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
