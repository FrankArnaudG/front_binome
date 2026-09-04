import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_scope.dart';
import 'roman_photo_download_service.dart';
import 'roman_photo_local_db.dart';
import 'roman_photo_purchase_flow.dart';
import 'roman_photo_story.dart';

/// Lecteur "roman-photo" façon magazine — feuillette les pages d'un
/// [RomanPhotoVolume] comme un vrai numéro (une page = un épisode déjà
/// composé), avec zoom pour lire les bulles de dialogue de près.
///
/// Aucune page n'est jamais chargée depuis le réseau ici (voir demande
/// utilisateur : seule la couverture de l'étagère se charge automatiquement,
/// pour ne pas consommer de données/ralentir sans que l'utilisateur l'ait
/// demandé) — tant que ce tome n'a pas été explicitement téléchargé (voir
/// RomanPhotoDownloadService), cet écran affiche seulement une invitation à
/// le télécharger (voir _NotDownloadedView). Une fois téléchargé, les pages
/// viennent exclusivement de la base SQLite locale (voir RomanPhotoLocalDb).
///
/// Capture d'écran bloquée tant que cet écran est ouvert (voir
/// initState/dispose) — best-effort : réellement empêchée sur Android, sur
/// iOS le système ne permet qu'une détection (voir doc du plugin
/// screen_protector), aucune app tierce ne peut bloquer une capture iOS.
class RomanPhotoReaderScreen extends StatefulWidget {
  final RomanPhotoVolume volume;
  final String storyId;

  const RomanPhotoReaderScreen({super.key, required this.volume, required this.storyId});

  @override
  State<RomanPhotoReaderScreen> createState() => _RomanPhotoReaderScreenState();
}

class _RomanPhotoReaderScreenState extends State<RomanPhotoReaderScreen> {
  late final PageController _pageController = PageController();
  int _page = 0;

  // Un pincer-zoomer (2 doigts) à l'intérieur d'un PageView se fait sinon
  // voler par le HorizontalDragGestureRecognizer du PageView, qui gagne
  // l'arène de gestes avant que l'InteractiveViewer de la page ait pu
  // réagir — le zoom ne se déclenchait jamais. Dès qu'un 2ᵉ doigt touche
  // l'écran, on coupe le défilement de pages le temps du geste, pour
  // laisser l'InteractiveViewer de la page recevoir le pincement.
  int _activePointers = 0;
  // Reste coupé tant que la page courante est zoomée (même après avoir
  // relâché un doigt) — sinon, glisser à un seul doigt sur une image déjà
  // zoomée fait à la fois défiler la page ET déplacer l'image zoomée.
  bool _zoomedIn = false;

  // `null` tant que la vérification locale n'est pas terminée (voir
  // _refreshLocalPages) — évite d'afficher à tort l'invitation à
  // télécharger le temps de cette vérification, purement locale (aucun
  // aller-retour réseau).
  List<Uint8List>? _localPages;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _enableScreenshotProtection();
    _refreshLocalPages();
  }

  @override
  void dispose() {
    _disableScreenshotProtection();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _enableScreenshotProtection() async {
    try {
      await ScreenProtector.preventScreenshotOn();
    } catch (_) {
      // Plateforme non supportée par le plugin (desktop/web) — la lecture
      // reste possible, juste sans cette protection.
    }
  }

  Future<void> _disableScreenshotProtection() async {
    try {
      await ScreenProtector.preventScreenshotOff();
    } catch (_) {}
  }

  Future<void> _refreshLocalPages() async {
    // Ne doit jamais laisser `_checked` bloqué à faux — une erreur de
    // lecture locale (imprévue) retombe sur "pas encore téléchargé" plutôt
    // que sur un loader qui tourne indéfiniment.
    List<Uint8List>? pages;
    try {
      pages = await RomanPhotoLocalDb.instance.loadPages(widget.volume.id);
    } catch (_) {
      pages = null;
    }
    if (mounted) {
      setState(() {
        _localPages = pages;
        _checked = true;
      });
    }
  }

  // Vrai seulement si le téléchargement a réussi (aucune exception) mais que
  // la relecture immédiate n'a quand même pas donné de pages — la bascule
  // automatique vers la lecture (voir build, pilotée par _localPages) reste
  // TOUJOURS le chemin prioritaire ; ce drapeau ne sert qu'à proposer un
  // bouton "Commencer à lire" en repli si jamais elle ne s'est pas produite,
  // plutôt que de laisser l'utilisateur bloqué sur l'invitation à
  // télécharger un tome pourtant déjà téléchargé.
  bool _downloadSucceededButNotShown = false;

  Future<void> _download() async {
    // Achat obligatoire AVANT le téléchargement pour un tome payant (voir
    // demande utilisateur) — no-op immédiat si gratuit ou déjà acheté.
    if (!await ensureRomanPhotoVolumePurchased(context, widget.volume)) return;
    if (!mounted) return;
    setState(() => _downloadSucceededButNotShown = false);
    try {
      await RomanPhotoDownloadService.instance.download(widget.volume, widget.storyId);
      await _refreshLocalPages();
      if (mounted && _localPages == null) {
        setState(() => _downloadSucceededButNotShown = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(LocaleScope.of(context).t('roman_photo_download_error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final pages = _localPages;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle.copyWith(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        foregroundColor: Colors.white,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.volume.titleFor(localeCode),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
            ),
            if (pages != null)
              Text(
                'Épisode ${_page + 1} / ${pages.length}',
                style: GoogleFonts.nunito(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (pages == null)
            ValueListenableBuilder<double?>(
              valueListenable: RomanPhotoDownloadService.instance.progressFor(widget.volume.id),
              builder: (context, progress, _) {
                if (progress == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, value: progress, color: Colors.white),
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: !_checked
            ? const Center(child: CircularProgressIndicator(color: Colors.white38))
            : (pages == null
                  ? _NotDownloadedView(
                      volume: widget.volume,
                      onDownload: _download,
                      showRetryReadInstead: _downloadSucceededButNotShown,
                      onRetryRead: _refreshLocalPages,
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Listener(
                            onPointerDown: (_) => setState(() => _activePointers++),
                            onPointerUp: (_) => setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
                            onPointerCancel: (_) =>
                                setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
                            child: PageView.builder(
                              controller: _pageController,
                              physics: (_activePointers >= 2 || _zoomedIn)
                                  ? const NeverScrollableScrollPhysics()
                                  : const PageScrollPhysics(),
                              itemCount: pages.length,
                              onPageChanged: (index) => setState(() => _page = index),
                              itemBuilder: (context, index) => _RomanPhotoPage(
                                bytes: pages[index],
                                onZoomChanged: (zoomed) {
                                  if (zoomed != _zoomedIn) {
                                    setState(() => _zoomedIn = zoomed);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(pages.length, (index) {
                            final active = index == _page;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active ? theme.primary : Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                      ],
                    )),
      ),
    );
  }
}

/// Invitation à télécharger — tout ce que voit l'utilisateur tant que ce
/// tome n'a pas été téléchargé (voir RomanPhotoReaderScreen, aucune page
/// n'est chargée depuis le réseau avant ce geste explicite).
class _NotDownloadedView extends StatelessWidget {
  final RomanPhotoVolume volume;
  final VoidCallback onDownload;
  // Voir _RomanPhotoReaderScreenState._downloadSucceededButNotShown — la
  // bascule automatique vers la lecture reste toujours prioritaire, ce
  // repli n'apparaît que si elle ne s'est exceptionnellement pas produite.
  final bool showRetryReadInstead;
  final VoidCallback onRetryRead;

  const _NotDownloadedView({
    required this.volume,
    required this.onDownload,
    required this.showRetryReadInstead,
    required this.onRetryRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download_outlined, color: theme.primary, size: 56),
            const SizedBox(height: 20),
            Text(
              t('roman_photo_not_downloaded_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              t('roman_photo_not_downloaded_text'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 13.5, height: 1.5, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<double?>(
              valueListenable: RomanPhotoDownloadService.instance.progressFor(volume.id),
              builder: (context, progress, _) {
                if (progress != null) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(
                          value: progress,
                          color: theme.primary,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).round()}%', style: GoogleFonts.nunito(color: Colors.white70)),
                    ],
                  );
                }
                if (showRetryReadInstead) {
                  return ElevatedButton.icon(
                    onPressed: onRetryRead,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(t('roman_photo_start_reading_cta')),
                  );
                }
                // Un tome payant pas encore acheté annonce l'achat sur ce
                // bouton (voir demande utilisateur : confirmer l'achat
                // AVANT de télécharger) — la confirmation elle-même se fait
                // dans la boîte de dialogue ouverte par onDownload (voir
                // ensureRomanPhotoVolumePurchased), le téléchargement
                // n'arrive qu'après.
                return ElevatedButton.icon(
                  onPressed: onDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: Icon(volume.needsPurchase ? Icons.shopping_cart_rounded : Icons.download_rounded),
                  label: Text(
                    volume.needsPurchase
                        ? t('roman_photo_purchase_price', {'price': '${volume.coinPrice}'})
                        : t('roman_photo_download_cta', {'count': '${volume.pageAssets.length}'}),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Une page pleine largeur, zoomable (pincer pour lire les bulles de près) —
/// même geste qu'une vraie liseuse de magazine plutôt qu'une image fixe.
/// Toujours depuis la base locale (voir RomanPhotoLocalDb) — cet écran
/// n'affiche jamais de page tant qu'elle n'a pas été téléchargée.
class _RomanPhotoPage extends StatefulWidget {
  final Uint8List bytes;
  final ValueChanged<bool> onZoomChanged;

  const _RomanPhotoPage({required this.bytes, required this.onZoomChanged});

  @override
  State<_RomanPhotoPage> createState() => _RomanPhotoPageState();
}

class _RomanPhotoPageState extends State<_RomanPhotoPage> {
  final _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    // Échelle actuelle = norme du premier vecteur colonne de la matrice —
    // évite d'avoir à suivre soi-même l'échelle pendant le geste.
    final scale = _controller.value.getMaxScaleOnAxis();
    widget.onZoomChanged(scale > 1.01);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 1,
      maxScale: 3.5,
      child: Center(
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.image_not_supported_rounded, color: Colors.white38, size: 48),
        ),
      ),
    );
  }
}
