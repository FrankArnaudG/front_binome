import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/box.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../box/box_scope.dart';
import 'day_counter_phrases.dart';

/// Compteur de jours du Dashboard — l'indicateur clé du couple, mis en
/// avant avec un grand chiffre et une phrase qui évolue avec la durée
/// (voir [_evolvingPhrase]). Suit le thème personnel choisi (voir
/// [ThemeScope]), utilisé uniquement par [DashboardTab].
///
/// Les phrases évolutives suivent la langue choisie dans les Paramètres
/// (voir [dayCounterPhraseTiersFor]) — fr/en/de/es/zh ont une vraie
/// traduction, moore/dioula retombent sur le français.
///
/// La date utilisée (voir [Box.togetherSince]) est corrigible via le petit
/// crayon : par défaut c'est la date de jumelage technique dans l'app
/// (paired_at), mais un couple peut être ensemble depuis bien plus
/// longtemps — l'écart entre "date d'inscription" et "vraie histoire" était
/// justement le souci signalé.
///
/// L'icône cœur (voir [Box.photoUrl]) peut être remplacée par une photo de
/// couple, choisie au tap — tant qu'aucune n'a été mise, la carte reste un
/// profil classique avec le cœur générique.
class DarkDayCounterCard extends StatefulWidget {
  final Box? box;

  /// true dans "Notre Bulle à nous" (CoupleProfileScreen) : les commandes
  /// d'édition (caméra, crayon) y restent visibles en permanence, cet
  /// écran étant justement l'endroit dédié pour les retoucher. false par
  /// défaut (Dashboard "Duo") : une fois une photo/date déjà personnalisée,
  /// l'icône correspondante s'efface pour garder la carte épurée — seule
  /// celle qui reste pertinente (pas encore renseignée) continue d'inviter
  /// au tap.
  final bool alwaysShowEditControls;

  /// `false` depuis CoupleProfileScreen (voir demande utilisateur) : le
  /// texte "Ensemble depuis..." juste au-dessus, dans le même écran, porte
  /// désormais son propre crayon dédié — inutile de le dupliquer ici, qui
  /// devient un simple affichage de lecture pour la date. Reste `true`
  /// ailleurs (Dashboard), seul endroit où ce crayon-ci existe encore.
  final bool showDateEditControl;

  /// Ouvre "Notre Bulle à nous" au tap sur la zone texte de la carte (voir
  /// _DarkDayCounterCardState.build) — `null` désactive ce geste (utilisé
  /// depuis CoupleProfileScreen elle-même, pas la peine de se rouvrir soi-même).
  final VoidCallback? onOpenProfile;

  const DarkDayCounterCard({
    super.key,
    required this.box,
    this.alwaysShowEditControls = false,
    this.showDateEditControl = true,
    this.onOpenProfile,
  });

  @override
  State<DarkDayCounterCard> createState() => _DarkDayCounterCardState();
}

class _DarkDayCounterCardState extends State<DarkDayCounterCard> {
  // 52 lisait comme un simple badge d'icône, pas une vraie photo de
  // profil — encore agrandi au-delà de la taille d'avatar standard
  // (_PersonColumn en fait 72) pour que la carte "jours ensemble" mette
  // vraiment la photo en avant.
  static const _avatarSize = 88.0;

  bool _saving = false;
  bool _photoBusy = false;

  /// Palier le plus élevé atteint par [days], dans la langue [localeCode] —
  /// voir [dayCounterPhraseTiersFor] (jour par jour la 1ère semaine, semaine
  /// par semaine le 1er mois, mois par mois la 1ère année, puis année par
  /// année de 1 à 100 ans).
  static String _evolvingPhrase(int days, String localeCode) {
    final tiers = dayCounterPhraseTiersFor(localeCode);
    for (final (threshold, phrase) in tiers) {
      if (days >= threshold) return phrase;
    }
    return tiers.last.$2;
  }

  Future<void> _editTogetherSince() async {
    final box = widget.box;
    if (box == null) return;
    // Capturé avant l'await : BoxScope.of(context) après le date picker
    // utiliserait un context potentiellement démonté (même raison que
    // _MottoCard côté CoupleProfileScreen).
    final boxService = BoxScope.of(context);
    final t = LocaleScope.of(context).t;
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: box.togetherSince ?? now,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: t('together_since_picker_title'),
    );
    if (picked == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await boxService.updateSettings(togetherSince: picked);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _choosePhotoAction() async {
    if (widget.box == null || _photoBusy) return;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final hasPhoto = widget.box!.photoUrl != null;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // En premier quand une photo existe déjà : consulter est
            // l'action la plus probable, avant de vouloir la changer.
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.visibility_rounded, color: theme.primary),
                title: Text(
                  t('photo_view'),
                  style: GoogleFonts.nunito(color: theme.textOnBackground),
                ),
                onTap: () => Navigator.of(ctx).pop(_PhotoAction.view),
              ),
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: theme.primary),
              title: Text(
                t('photo_camera'),
                style: GoogleFonts.nunito(color: theme.textOnBackground),
              ),
              onTap: () => Navigator.of(ctx).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: theme.primary),
              title: Text(
                t('photo_gallery'),
                style: GoogleFonts.nunito(color: theme.textOnBackground),
              ),
              onTap: () => Navigator.of(ctx).pop(_PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  t('photo_remove'),
                  style: GoogleFonts.nunito(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(ctx).pop(_PhotoAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == _PhotoAction.view) {
      final url = widget.box?.photoUrl;
      if (url != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _CouplePhotoViewer(url: url)),
        );
      }
      return;
    }

    if (action == _PhotoAction.remove) {
      await _removePhoto();
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: action == _PhotoAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    await _uploadPhoto(File(picked.path));
  }

  Future<void> _uploadPhoto(File file) async {
    final boxService = BoxScope.of(context);
    setState(() => _photoBusy = true);
    try {
      await boxService.uploadPhoto(file);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('photo_upload_error'))),
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    final boxService = BoxScope.of(context);
    setState(() => _photoBusy = true);
    try {
      await boxService.deletePhoto();
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final locale = LocaleScope.of(context);
    final t = locale.t;
    final togetherSince = widget.box?.togetherSince;
    final days = togetherSince != null
        ? DateTime.now().difference(togetherSince).inDays
        : null;
    final photoUrl = widget.box?.photoUrl;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (theme.isDark ? Colors.white : Colors.black).withValues(
            alpha: 0.06,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.box != null ? _choosePhotoAction : null,
            child: SizedBox(
              // Exactement la taille du cercle : le badge se positionne en
              // négatif par-dessus son bord (clipBehavior: Clip.none) —
              // un conteneur plus grand que l'avatar le laissait plaqué en
              // haut à gauche, avec le badge qui flottait loin du bord
              // réel du cercle au lieu d'être dessus (constaté en réel).
              width: _avatarSize,
              height: _avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: _avatarSize,
                    height: _avatarSize,
                    child: ClipOval(
                      child: photoUrl != null
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              // Repli sur la silhouette générique si
                              // l'image ne charge pas (lien cassé, hors
                              // ligne...) — un profil classique reste
                              // toujours affiché.
                              errorBuilder: (context, error, stackTrace) =>
                                  _profileFallback(theme),
                            )
                          : _profileFallback(theme),
                    ),
                  ),
                  if ((widget.alwaysShowEditControls || photoUrl == null) &&
                      !_photoBusy)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.primary,
                          border: Border.all(color: theme.surface, width: 2),
                        ),
                        child: const Icon(
                          Icons.add_a_photo_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (_photoBusy)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              // Zone dédiée à la navigation (voir onOpenProfile) — pas
              // l'avatar/le crayon, qui ont leurs propres gestes.
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (days != null)
                    // FittedBox plutôt qu'un Row nu : "togetherSince" pouvant
                    // désormais remonter loin dans le passé (voir Box), le
                    // compteur peut afficher 4 chiffres et plus — un Row seul
                    // débordait alors hors de la carte (constaté en réel).
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$days',
                            style: GoogleFonts.poppins(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: theme.primary,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              days > 1
                                  ? t('day_counter_unit_other')
                                  : t('day_counter_unit_one'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: theme.textOnBackground,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      t('day_counter_start'),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.textOnBackground,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    days != null
                        ? _evolvingPhrase(days, locale.current.code)
                        : t('day_counter_start_sub'),
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: theme.textOnBackgroundMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showDateEditControl &&
              widget.box != null &&
              (widget.alwaysShowEditControls ||
                  widget.box!.togetherSinceOverride == null))
            _saving
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.textOnBackgroundMuted,
                      ),
                    ),
                  )
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: theme.textOnBackgroundMuted,
                    ),
                    onPressed: _editTogetherSince,
                  ),
        ],
      ),
    );
  }

  // Silhouette grise neutre façon "profil classique sans photo" — pas de
  // dégradé (retiré, ne plaisait pas). Deux silhouettes plutôt qu'une
  // seule : cette photo représente le COUPLE, pas une seule personne. Bien
  // plus grande que le cercle qui la contient (0.8, pas 0.5) pour
  // vraiment l'occuper plutôt que flotter avec une grande marge vide.
  Widget _profileFallback(ThemePalette theme) {
    return Container(
      color: theme.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : const Color(0xFFE0E0E0),
      child: Icon(
        Icons.people_alt_rounded,
        color: theme.isDark
            ? Colors.white.withValues(alpha: 0.4)
            : const Color(0xFF9E9E9E),
        size: _avatarSize * 0.8,
      ),
    );
  }
}

enum _PhotoAction { view, camera, gallery, remove }

/// Visionneuse plein écran pour la photo de couple — plus simple que
/// [PhotoViewerScreen] (Jardin secret) : une seule image, pas de
/// défilement/suppression multi-photos, juste zoom + fermeture.
class _CouplePhotoViewer extends StatelessWidget {
  final String url;

  const _CouplePhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
