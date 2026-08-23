import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game_box.dart';
import '../../../theme/theme_palette.dart';
import 'game_box_icon.dart';

/// Composants partagés par les écrans de pioche à cartes (voir
/// GameBoxSessionScreen et TruthOrDareSessionScreen) : le retournement 3D,
/// les faces de carte génériques, les actions d'envoi, l'archive et le
/// dialogue de fin de boîte sont identiques d'un gabarit de jeu à l'autre —
/// seule la façon de constituer/choisir la carte à retourner diffère.

/// Choisit une des façons de désigner le/la partenaire sur le bouton
/// d'envoi — jamais toujours le prénom, pour que l'utilisateur voie autre
/// chose à chaque fois plutôt qu'un bouton figé. Le tirage est dérivé de
/// [seed] (l'id de la carte affichée) plutôt que réellement aléatoire : il
/// reste stable tant que la même carte est à l'écran, et change dès qu'une
/// autre carte est choisie — un vrai Random() re-tirerait à chaque
/// rebuild (changement d'état "sending", etc.), ce qui ferait clignoter le
/// texte du bouton.
///
/// "binôme"/"moitié"/"amour" sont grammaticalement invariables (leur genre
/// grammatical ne dépend pas de celui de la personne désignée) — seul
/// "partenaire" a besoin du genre réel du/de la partenaire pour accorder
/// "mon"/"ma" ; un genre personnalisé (texte libre saisi par la personne,
/// voir ProfileCompletionScreen) retombe sur "mon/ma partenaire". Première
/// personne ("ma moitié" plutôt que "ta moitié") — voir demande
/// utilisateur : le bouton se lit comme l'action de CELUI qui envoie, pas
/// comme une injonction adressée au destinataire.
String partnerSendLabel(BuildContext context, AppUser? partner, String seed) {
  final t = LocaleScope.of(context).t;
  final prenom = partner?.prenom.trim();
  final options = <String>[
    if (prenom != null && prenom.isNotEmpty) prenom,
    t('game_partner_option_partner', {'possessive': _partnerPossessive(partner?.gender)}),
    t('game_partner_option_soulmate'),
    t('game_partner_option_other_half'),
    t('game_partner_option_love'),
  ];
  final index = seed.hashCode.abs() % options.length;
  return '${t('game_send_to_prefix')} ${options[index]}';
}

String _partnerPossessive(String? gender) {
  switch (gender) {
    case 'Homme':
      return 'mon';
    case 'Femme':
      return 'ma';
    default:
      return 'mon/ma';
  }
}

/// Choisit comment désigner le/la partenaire dans l'en-tête d'une
/// discussion (voir GameCardThreadScreen) — tirage entre son prénom et les
/// petits noms que l'utilisateur·rice courant·e lui a donnés (voir
/// CoupleProfileScreen._editNicknames, `AppUser.loveName` — MES petits
/// noms pour MON binôme, jamais les siens pour moi). Même principe de
/// stabilité que [partnerSendLabel] : dérivé de [seed] (l'id du fil/de la
/// carte) plutôt que d'un vrai Random(), pour ne pas changer à chaque
/// reconstruction de l'écran — seulement d'une discussion à l'autre.
String partnerDisplayName(AppUser? partner, List<String> loveNames, String seed) {
  final prenom = partner?.prenom.trim();
  final fallback = (prenom != null && prenom.isNotEmpty) ? prenom : (partner?.name ?? 'Ton binôme');
  final options = <String>[fallback, ...loveNames.where((n) => n.trim().isNotEmpty)];
  if (options.length == 1) return options.first;
  final index = seed.hashCode.abs() % options.length;
  return options[index];
}

/// Petite carte décalée derrière la carte active, pour simuler l'épaisseur
/// de la pioche restante.
class DeckShadowCard extends StatelessWidget {
  final ThemePalette theme;

  const DeckShadowCard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 280,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.15)),
      ),
    );
  }
}

/// Enrobe le retournement 3D (dos → face) piloté par [flip] — voir son
/// usage dans les deux écrans de pioche.
class FlippableCard extends StatelessWidget {
  final AnimationController flip;
  final Widget back;
  final Widget front;

  const FlippableCard({super.key, required this.flip, required this.back, required this.front});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flip,
      builder: (context, _) {
        final angle = flip.value * math.pi;
        final showingFront = flip.value < 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          child: showingFront
              ? back
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: front,
                ),
        );
      },
    );
  }
}

class GameCardBack extends StatelessWidget {
  final ThemePalette theme;
  final GameBox box;

  const GameCardBack({super.key, required this.theme, required this.box});

  @override
  Widget build(BuildContext context) {
    final hasImage = box.imagePath != null;

    return Container(
      width: 200,
      height: 280,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: hasImage
            ? null
            : LinearGradient(
                colors: [theme.primary, theme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: theme.primary.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      // Même logique que _FanCardFace (game_box_session_screen.dart) :
      // l'image (voir GameBox.imagePath) recouvre toute la carte pendant le
      // retournement, pas seulement l'éventail de sélection — sinon elle
      // disparaît visuellement dès qu'on tape sur la carte pour révéler la
      // question (constaté en réel : ce widget-ci, distinct de
      // _FanCardFace, n'avait jamais reçu la même logique).
      child: hasImage
          ? Image.network(
              box.imagePath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Icon(iconForGameBox(box.iconKey), color: Colors.white.withValues(alpha: 0.85), size: 46),
              ),
            )
          : Center(
              child: Icon(iconForGameBox(box.iconKey), color: Colors.white.withValues(alpha: 0.85), size: 46),
            ),
    );
  }
}

class GameCardFront extends StatelessWidget {
  final ThemePalette theme;
  final String text;
  final String? badge;
  final Color? badgeColor;

  const GameCardFront({super.key, required this.theme, required this.text, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 280,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: (badgeColor ?? theme.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge!,
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: badgeColor ?? theme.primary),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: theme.textOnBackground),
          ),
        ],
      ),
    );
  }
}

class GameCardActions extends StatelessWidget {
  final ThemePalette theme;
  final String sendLabel;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onBack;
  final String? backLabel;

  const GameCardActions({
    super.key,
    required this.theme,
    required this.sendLabel,
    required this.sending,
    required this.onSend,
    required this.onBack,
    this.backLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: sending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: sending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          ),
                        )
                      : Text(
                          sendLabel,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: sending ? null : onBack,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              backLabel ?? LocaleScope.of(context).t('game_choose_another_card'),
              style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Petit cadre d'archive : une mini-pile inclinée des cartes déjà envoyées
/// par ce/cette joueur·se — donne un aperçu visuel de la progression
/// directement sur l'écran de la pioche.
class GameArchiveTray extends StatelessWidget {
  final ThemePalette theme;
  final GameBox box;
  final int count;
  final VoidCallback onTap;

  const GameArchiveTray({super.key, required this.theme, required this.box, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(left: 6, child: Transform.rotate(angle: 0.14, child: _MiniArchiveCard(theme: theme, box: box, dim: true))),
                    Positioned(left: 3, child: Transform.rotate(angle: 0.04, child: _MiniArchiveCard(theme: theme, box: box, dim: true))),
                    Positioned(left: 0, child: Transform.rotate(angle: -0.06, child: _MiniArchiveCard(theme: theme, box: box, dim: false))),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text(
                count > 0
                    ? LocaleScope.of(context).t(
                        count > 1 ? 'game_cards_sent_count_other' : 'game_cards_sent_count_one',
                        {'count': '$count'},
                      )
                    : LocaleScope.of(context).t('game_continue_playing'),
                style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.textOnBackgroundMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniArchiveCard extends StatelessWidget {
  final ThemePalette theme;
  final GameBox box;
  final bool dim;

  const _MiniArchiveCard({required this.theme, required this.box, required this.dim});

  @override
  Widget build(BuildContext context) {
    final hasImage = box.imagePath != null && box.imagePath!.isNotEmpty;

    return Container(
      width: 26,
      height: 36,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primary.withValues(alpha: dim ? 0.35 : 0.65),
            theme.secondary.withValues(alpha: dim ? 0.35 : 0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.8),
      ),
      // L'image de la boîte (voir GameBox.imagePath, réglable depuis
      // l'espace admin) remplace l'icône générique dès qu'elle existe —
      // même principe que la carte de l'éventail (voir _FanCardFace).
      child: hasImage
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  box.imagePath!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(iconForGameBox(box.iconKey), color: Colors.white.withValues(alpha: dim ? 0.7 : 0.9), size: 12),
                ),
                if (dim) Container(color: Colors.black.withValues(alpha: 0.35)),
              ],
            )
          : Icon(iconForGameBox(box.iconKey), color: Colors.white.withValues(alpha: dim ? 0.7 : 0.9), size: 12),
    );
  }
}

class GameBoxCompletionDialog extends StatelessWidget {
  final ThemePalette theme;
  final String boxTitle;

  const GameBoxCompletionDialog({super.key, required this.theme, required this.boxTitle});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: theme.primary, size: 40),
            const SizedBox(height: 14),
            Text(
              'Boîte terminée !',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: theme.textOnBackground),
            ),
            const SizedBox(height: 8),
            Text(
              '« $boxTitle » n\'a plus de secrets pour toi 💗',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.primary),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
