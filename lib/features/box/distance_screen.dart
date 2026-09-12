import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:permission_handler/permission_handler.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../core/api_client.dart';
import '../../core/live_location_service.dart';
import '../../models/app_user.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'box_service.dart';

/// "Notre distance" (voir demande utilisateur) — partage PONCTUEL de
/// position, JAMAIS un suivi continu : un seul relevé GPS par tap sur
/// "Partager ma position", aucune tâche de fond. Vraie carte (fond
/// OpenStreetMap via flutter_map, voir demande utilisateur) avec les deux
/// avatars positionnés à leurs coordonnées réelles et reliés par une ligne
/// — choisi plutôt que Google Maps pour ne nécessiter aucune clé API/compte
/// Google Cloud (dans l'esprit de la contrainte validée précédemment).
/// Contrairement à Google Maps Timeline, pas de lecture/historique de
/// trajet : un simple relevé du jour, pas un suivi continu.
class DistanceScreen extends StatefulWidget {
  final AppUser user;

  const DistanceScreen({super.key, required this.user});

  @override
  State<DistanceScreen> createState() => _DistanceScreenState();
}

class _DistanceScreenState extends State<DistanceScreen> with SingleTickerProviderStateMixin {
  bool _sharing = false;
  String? _error;
  bool _liveSharingBusy = false;
  bool _refreshing = false;
  bool _settingHome = false;
  // Anime l'icône de rafraîchissement pendant l'appel (voir demande
  // utilisateur : "ça doit faire une rotation... pour dire que l'action
  // s'est bien passée") — tourne en continu tant que ça charge, s'arrête
  // net dès que la réponse arrive.
  late final AnimationController _refreshIconController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  // Écoute de 'BoxLocationShared' désormais globale (voir BoxService,
  // même principe que DoodleNotifier) — la position reste à jour même si
  // on n'est pas sur cet écran au moment où le binôme la partage. Cet
  // écran n'a donc plus besoin de sa propre souscription : il lui suffit
  // d'écouter BoxService.instance (voir AnimatedBuilder ci-dessous), déjà
  // notifié à chaque mise à jour.

  @override
  void dispose() {
    _refreshIconController.dispose();
    super.dispose();
  }

  /// Filet de secours (voir demande utilisateur) — le temps réel
  /// ci-dessus n'est jamais la seule source de vérité dans cette app
  /// (même principe que TimelineScreen/BoxWaitingScreen) : un événement
  /// manqué (coupure, app en arrière-plan pile à ce moment...) ne doit
  /// jamais laisser cet écran bloqué sur une distance périmée sans recours.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    _refreshIconController.repeat();
    try {
      await BoxService.instance.fetchCurrent();
    } catch (_) {
      // Best-effort — l'écran garde silencieusement ce qu'il affichait déjà.
    } finally {
      _refreshIconController.stop();
      _refreshIconController.value = 0;
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _shareLocation() async {
    if (_sharing) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted && !status.isLimited) {
        setState(() => _error = "Autorise l'accès à ta position pour la partager.");
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _error = 'Active la localisation sur ton téléphone.');
        return;
      }

      // Sans limite de temps, un GPS qui ne trouve jamais de position
      // (intérieur, émulateur sans provider configuré...) laissait le
      // bouton tourner indéfiniment — voir demande utilisateur : "ça
      // tourne toujours". Passé ce délai, on retombe dans le catch
      // générique ci-dessous plutôt que de rester bloqué.
      final position = await Geolocator.getCurrentPosition(
        // Précision maximale (voir demande utilisateur : "ça ne vaut pas
        // un mètre" — un écart de quelques mètres reste normal, propre à
        // la marge d'erreur physique du GPS, mais "best" la réduit par
        // rapport à "medium").
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)),
      );
      await BoxService.instance.shareLocation(latitude: position.latitude, longitude: position.longitude);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      // Journalisé (voir demande utilisateur : diagnostiquer un futur échec
      // — GPS expiré vs réseau vers le serveur, indiscernables jusqu'ici
      // dans le message générique affiché ci-dessous).
      debugPrint('DistanceScreen: partage de position échoué ($e)');
      setState(() => _error = "Impossible de récupérer ta position pour l'instant.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Enregistre la position GPS actuelle comme repère "maison" (voir
  /// demande utilisateur : "on pourrait ajouter la position de la maison
  /// sur la carte") — partagé par la Box, modifiable à tout moment par
  /// n'importe lequel des deux (voir BoxService.setHomeLocation).
  Future<void> _setHomeHere() async {
    if (_settingHome) return;
    setState(() {
      _settingHome = true;
      _error = null;
    });
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted && !status.isLimited) {
        setState(() => _error = "Autorise l'accès à ta position pour définir la maison.");
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _error = 'Active la localisation sur ton téléphone.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)),
      );
      await BoxService.instance.setHomeLocation(latitude: position.latitude, longitude: position.longitude);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      debugPrint('DistanceScreen: définition de la maison échouée ($e)');
      setState(() => _error = "Impossible de récupérer ta position pour l'instant.");
    } finally {
      if (mounted) setState(() => _settingHome = false);
    }
  }

  /// Interrupteur "partage en direct" (voir LiveLocationService) — demande
  /// la permission ICI, avec le contexte visible de pourquoi (jamais depuis
  /// le service lui-même), au moment précis où la personne l'active.
  Future<void> _onToggleLiveSharing(bool value) async {
    if (_liveSharingBusy) return;
    setState(() {
      _liveSharingBusy = true;
      _error = null;
    });
    try {
      if (value) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted && !status.isLimited) {
          if (mounted) setState(() => _error = "Autorise l'accès à ta position pour activer le partage en direct.");
          return;
        }
      }
      await LiveLocationService.instance.setEnabled(value);
    } finally {
      if (mounted) setState(() => _liveSharingBusy = false);
    }
  }

  /// En dessous de 1 km, affiche des mètres plutôt que d'arrondir à "0 km"
  /// (voir demande utilisateur) — peu parlant quand on est très proches
  /// l'un de l'autre.
  String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.round()} km';
  }

  String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  /// Ouvre la feuille contenant tout ce qui était auparavant sous la carte
  /// (voir demande utilisateur : "occuper tout l'écran... un bouton qui
  /// fait sortir un modale où il y a le nécessaire") — la carte reste
  /// affichée en plein écran derrière, seule cette feuille défile.
  void _openOptionsSheet() {
    final theme = ThemeScope.paletteOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final box = BoxService.instance.currentBox;
          final me = widget.user.id;
          final myLocation = box?.locationOf(me);
          final partnerId = box != null ? (box.creatorId == me ? box.partnerId : box.creatorId) : null;
          final partnerLocation = partnerId != null ? box?.locationOf(partnerId) : null;

          Future<void> runAndRefreshSheet(Future<void> Function() action) async {
            await action();
            setSheetState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (myLocation != null || partnerLocation != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (myLocation != null)
                          Text('Toi : ${_relativeTime(myLocation.at)}',
                              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                        if (partnerLocation != null)
                          Text('Ton binôme : ${_relativeTime(partnerLocation.at)}',
                              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Interrupteur "partage en direct" (voir demande
                  // utilisateur : "dès que l'application est ouverte") —
                  // DÉSACTIVÉ par défaut, jamais en arrière-plan (voir
                  // LiveLocationService), le partage ponctuel ci-dessous
                  // reste disponible que l'interrupteur soit activé ou non.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(16)),
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: LiveLocationService.instance.enabled,
                      onChanged: _liveSharingBusy
                          ? null
                          : (value) => runAndRefreshSheet(() => _onToggleLiveSharing(value)),
                      activeColor: theme.primary,
                      title: Text(
                        'Partage en direct',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                      ),
                      subtitle: Text(
                        "Ta position se met à jour automatiquement tant que l'app est ouverte — s'arrête dès que tu la fermes.",
                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.nunito(fontSize: 13, color: Colors.redAccent)),
                    const SizedBox(height: 12),
                  ],
                  // Voir demande utilisateur : "si la position est déjà
                  // partagée, le bouton Partager ma position n'a plus
                  // d'intérêt" — tant que le partage en direct est actif,
                  // ce bouton devient l'action inverse (couper le partage)
                  // plutôt qu'un relevé ponctuel redondant avec ce que le
                  // flux en direct fait déjà tout seul.
                  if (LiveLocationService.instance.enabled)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _liveSharingBusy ? null : () => runAndRefreshSheet(() => _onToggleLiveSharing(false)),
                        icon: _liveSharingBusy
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.textOnBackground))
                            : const Icon(Icons.location_off_rounded),
                        label: const Text('Couper le partage en direct'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: theme.textOnBackground,
                          side: BorderSide(color: theme.textOnBackgroundMuted),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _sharing ? null : () => runAndRefreshSheet(_shareLocation),
                        icon: _sharing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.my_location_rounded),
                        label: Text(_sharing ? 'Localisation...' : 'Partager ma position'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    LiveLocationService.instance.enabled
                        ? 'Partage en direct actif tant que l\'app reste ouverte.'
                        : 'Jamais de suivi en continu — juste un relevé ponctuel à chaque tap.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  // Repère "maison" (voir demande utilisateur : "on pourrait
                  // ajouter la position de la maison sur la carte") — utilise
                  // la position GPS actuelle, comme "Partager ma position".
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _settingHome ? null : () => runAndRefreshSheet(_setHomeHere),
                      icon: _settingHome
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary))
                          : const Icon(Icons.home_rounded),
                      label: Text(
                        box?.homeLocation != null ? 'Déplacer la maison ici' : 'Définir la maison ici',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: theme.primary,
                        side: BorderSide(color: theme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Affiche un repère maison sur la carte, à partir de ta position actuelle — visible par vous deux.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return AnimatedBuilder(
      animation: BoxService.instance,
      builder: (context, _) {
        final box = BoxService.instance.currentBox;
        final distance = box?.distanceKm;
        final me = widget.user.id;
        final myLocation = box?.locationOf(me);
        final partnerId = box != null ? (box.creatorId == me ? box.partnerId : box.creatorId) : null;
        final partnerLocation = partnerId != null ? box?.locationOf(partnerId) : null;
        final partner = box?.partnerOf(me);
        final home = box?.homeLocation;
        // Largeur dispo pour la rangée d'avatars (repli sans carte, voir
        // _DistanceAvatars) — 24 de chaque côté (padding de l'écran) + 20
        // de chaque côté (padding de la carte dégradée) = 88 au total.
        final avatarsMaxWidth = MediaQuery.sizeOf(context).width - 88;

        return Scaffold(
          backgroundColor: theme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: theme.statusBarOverlayStyle,
            foregroundColor: theme.textOnBackground,
            title: Text('Notre distance', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
            // Icône de rafraîchissement en haut à droite (voir demande
            // utilisateur) — en plus du geste tirer-pour-rafraîchir, pour
            // une action visible sans avoir à deviner le geste.
            actions: [
              RotationTransition(
                turns: _refreshIconController,
                child: IconButton(
                  onPressed: _refreshing ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Rafraîchir',
                ),
              ),
            ],
          ),
          // La carte occupe désormais TOUT l'écran (voir demande
          // utilisateur : "occupe très peu d'espace") — tout ce qui
          // affichait des infos/actions en dessous est déplacé dans la
          // feuille ouverte par le bouton flottant (voir _openOptionsSheet).
          body: myLocation != null || partnerLocation != null
              // Pas de RefreshIndicator ici : FlutterMap capte déjà le
              // geste de glissement pour déplacer la carte, un
              // tirer-pour-rafraîchir par-dessus ne se déclencherait
              // jamais — le bouton dans l'AppBar reste le moyen de
              // rafraîchir manuellement dans ce cas.
              ? _DistanceMapCard(
                  me: widget.user,
                  partner: partner,
                  myLocation: myLocation,
                  partnerLocation: partnerLocation,
                  home: home,
                  distanceKm: distance,
                  formatDistance: _formatDistance,
                )
              : RefreshIndicator(
                  color: theme.primary,
                  backgroundColor: theme.surface,
                  onRefresh: _refresh,
                  child: ThemedBackground(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                          child: Center(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Deux avatars côte à côte (PAS superposés
                                  // — voir demande utilisateur) reliés par un
                                  // cœur — repli tant qu'aucune position
                                  // n'est partagée (pas encore de
                                  // coordonnées sur lesquelles centrer une
                                  // carte).
                                  _DistanceAvatars(me: widget.user, partner: partner, distanceKm: distance, maxWidth: avatarsMaxWidth),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Position non partagée',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "l'un de vous deux n'a pas encore partagé la sienne",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.nunito(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _sharing ? null : _shareLocation,
                                      icon: _sharing
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.my_location_rounded),
                                      label: Text(_sharing ? 'Localisation...' : 'Partager ma position'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: theme.primary,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.nunito(fontSize: 12, color: Colors.white)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _openOptionsSheet,
            backgroundColor: theme.primary,
            tooltip: 'Options',
            child: const Icon(Icons.tune_rounded, color: Colors.white),
          ),
        );
      },
    );
  }
}

/// Deux avatars côte à côte (jamais superposés, contrairement au petit
/// badge du Dashboard) reliés par un cœur — pensé pour la grande carte
/// dégradée de cet écran (voir demande utilisateur, capture de référence).
///
/// L'écart entre les deux avatars reflète la distance réelle (voir demande
/// utilisateur : "en fonction de la distance les photos s'éloignent ou se
/// rapprochent") — sur une échelle logarithmique (une distance va de
/// quelques mètres à des milliers de km, un simple linéaire écraserait tout
/// en dessous de ~50 km à l'écart minimal), mais TOUJOURS borné à la
/// largeur réellement disponible (voir demande utilisateur : "elle ne doit
/// pas dépasser le cadre") via LayoutBuilder plutôt qu'un écart en dur.
class _DistanceAvatars extends StatelessWidget {
  final AppUser me;
  final AppUser? partner;
  final double? distanceKm;
  // Calculée par l'écran parent à partir de MediaQuery (voir
  // DistanceScreen.build) — PAS via LayoutBuilder ici : ce widget vit sous
  // un IntrinsicHeight (mise en page centrée du tirer-pour-rafraîchir), et
  // LayoutBuilder ne peut pas calculer de dimension intrinsèque (exception
  // Flutter), ce qui cassait le rendu de tout l'écran.
  final double maxWidth;

  const _DistanceAvatars({required this.me, required this.partner, required this.distanceKm, required this.maxWidth});

  static const double _avatarSize = 48;
  static const double _minSpacing = 10;
  // Distance au-delà de laquelle l'écart maximal (borné par le cadre) est
  // déjà atteint — au-delà, les avatars n'ont plus de raison de s'écarter
  // davantage, le cadre lui-même ne grandit pas.
  static const double _referenceKm = 300;

  @override
  Widget build(BuildContext context) {
    final availableWidth = maxWidth.isFinite && maxWidth > 0 ? maxWidth : _avatarSize * 2 + _minSpacing;
    final maxSpacing = math.max(_minSpacing, availableWidth - _avatarSize * 2 - 8);

    double spacing = maxSpacing * 0.4;
    if (distanceKm != null) {
      final t = (math.log(distanceKm! + 1) / math.log(_referenceKm + 1)).clamp(0.0, 1.0);
      spacing = _minSpacing + (maxSpacing - _minSpacing) * t;
    }

    return SizedBox(
      width: availableWidth,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _avatar(me.avatar, me.prenom),
              SizedBox(width: spacing),
              _avatar(partner?.avatar, partner?.prenom ?? ''),
            ],
          ),
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            alignment: Alignment.center,
            child: const Icon(Icons.favorite_rounded, color: Color(0xFFE63E7A), size: 15),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? avatarUrl, String prenom) {
    final initial = prenom.isNotEmpty ? prenom[0].toUpperCase() : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white24,
        backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
        child: avatarUrl == null
            ? Text(initial, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))
            : null,
      ),
    );
  }
}

/// Vraie carte (voir demande utilisateur, capture de référence : "je veux
/// que l'on puisse avoir une vue pareil") — fond OpenStreetMap via
/// flutter_map, les deux avatars positionnés à leurs coordonnées réelles,
/// reliés par une ligne pointillée avec la distance affichée dessus.
/// Centrée/zoomée automatiquement pour montrer les deux points (ou le seul
/// disponible si l'autre n'a pas encore partagé sa position). Un changement
/// de position (voir demande utilisateur : "si je me déplace, on me verra
/// bouger sur la carte") anime l'avatar en glissant vers le nouveau point
/// plutôt que de le faire sauter directement dessus (voir [_LatLngTween]).
class _DistanceMapCard extends StatefulWidget {
  final AppUser me;
  final AppUser? partner;
  final ({double lat, double lon, DateTime at})? myLocation;
  final ({double lat, double lon, DateTime at})? partnerLocation;
  final ({double lat, double lon})? home;
  final double? distanceKm;
  final String Function(double) formatDistance;

  const _DistanceMapCard({
    required this.me,
    required this.partner,
    required this.myLocation,
    required this.partnerLocation,
    required this.home,
    required this.distanceKm,
    required this.formatDistance,
  });

  @override
  State<_DistanceMapCard> createState() => _DistanceMapCardState();
}

class _DistanceMapCardState extends State<_DistanceMapCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(() {
      setState(() {
        if (_myAnim != null) _animatedMy = _myAnim!.value;
        if (_partnerAnim != null) _animatedPartner = _partnerAnim!.value;
      });
    });

  Animation<latlong.LatLng>? _myAnim;
  Animation<latlong.LatLng>? _partnerAnim;
  latlong.LatLng? _animatedMy;
  latlong.LatLng? _animatedPartner;
  // "En route vers la maison" (voir demande utilisateur) — déduit en
  // comparant, à chaque nouvelle position, la distance au repère maison
  // avant/après : si elle diminue nettement, on se rapproche. Pas de
  // véritable calcul d'itinéraire/cap, juste cette tendance simple.
  bool _meHeadingHome = false;
  bool _partnerHeadingHome = false;
  static const _distanceCalc = latlong.Distance();
  static const _headingHomeThresholdMeters = 15;
  // Points de départ, figés une seule fois — le cadrage initial de la
  // carte (voir CameraFit.coordinates ci-dessous) ne doit pas sauter à
  // chaque animation, seuls les avatars bougent.
  late final List<latlong.LatLng> _initialPoints = [
    if (_pointOf(widget.myLocation) != null) _pointOf(widget.myLocation)!,
    if (_pointOf(widget.partnerLocation) != null) _pointOf(widget.partnerLocation)!,
    if (widget.home != null) latlong.LatLng(widget.home!.lat, widget.home!.lon),
  ];

  static latlong.LatLng? _pointOf(({double lat, double lon, DateTime at})? loc) =>
      loc != null ? latlong.LatLng(loc.lat, loc.lon) : null;

  @override
  void initState() {
    super.initState();
    _animatedMy = _pointOf(widget.myLocation);
    _animatedPartner = _pointOf(widget.partnerLocation);
  }

  @override
  void didUpdateWidget(covariant _DistanceMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newMy = _pointOf(widget.myLocation);
    final newPartner = _pointOf(widget.partnerLocation);
    var shouldAnimate = false;

    final home = widget.home != null ? latlong.LatLng(widget.home!.lat, widget.home!.lon) : null;

    if (newMy != null && _animatedMy != null && newMy != _animatedMy) {
      if (home != null) {
        final oldDist = _distanceCalc.as(latlong.LengthUnit.Meter, _animatedMy!, home);
        final newDist = _distanceCalc.as(latlong.LengthUnit.Meter, newMy, home);
        if (newDist < oldDist - _headingHomeThresholdMeters) {
          _meHeadingHome = true;
        } else if (newDist > oldDist + _headingHomeThresholdMeters) {
          _meHeadingHome = false;
        }
      }
      _myAnim = _LatLngTween(begin: _animatedMy!, end: newMy).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      shouldAnimate = true;
    } else if (newMy != _animatedMy) {
      // Première apparition (ou disparition) de ce point — rien à
      // interpoler depuis "nulle part", on l'affiche directement.
      _myAnim = null;
      _animatedMy = newMy;
    }

    if (newPartner != null && _animatedPartner != null && newPartner != _animatedPartner) {
      if (home != null) {
        final oldDist = _distanceCalc.as(latlong.LengthUnit.Meter, _animatedPartner!, home);
        final newDist = _distanceCalc.as(latlong.LengthUnit.Meter, newPartner, home);
        if (newDist < oldDist - _headingHomeThresholdMeters) {
          _partnerHeadingHome = true;
        } else if (newDist > oldDist + _headingHomeThresholdMeters) {
          _partnerHeadingHome = false;
        }
      }
      _partnerAnim =
          _LatLngTween(begin: _animatedPartner!, end: newPartner).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      shouldAnimate = true;
    } else if (newPartner != _animatedPartner) {
      _partnerAnim = null;
      _animatedPartner = newPartner;
    }

    if (shouldAnimate) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final myPoint = _animatedMy;
    final partnerPoint = _animatedPartner;
    final points = _initialPoints;
    final homePoint = widget.home != null ? latlong.LatLng(widget.home!.lat, widget.home!.lon) : null;

    // Occupe tout l'espace disponible (voir demande utilisateur : "occuper
    // tout l'écran") — c'est désormais directement le corps du Scaffold,
    // plus une simple carte de hauteur fixe au milieu d'un écran défilable.
    return SizedBox.expand(
      child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.fromLTRB(40, 50, 40, 70),
                  maxZoom: 15,
                ),
                // Consultation uniquement (voir demande utilisateur : "pas
                // de suivi continu") — zoomer/déplacer pour explorer reste
                // possible, mais rien n'anime ni ne recentre tout seul.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.binome.app',
                ),
                if (myPoint != null && partnerPoint != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [myPoint, partnerPoint],
                        strokeWidth: 3,
                        color: theme.primary,
                        pattern: StrokePattern.dashed(segments: const [10, 8]),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    // Repère "maison" (voir demande utilisateur) — fixe,
                    // jamais animé (contrairement aux avatars ci-dessous).
                    if (homePoint != null)
                      Marker(
                        point: homePoint,
                        width: 40,
                        height: 40,
                        child: _homeMarker(theme),
                      ),
                    if (myPoint != null)
                      Marker(
                        point: myPoint,
                        width: 48,
                        height: 56,
                        child: _mapAvatar(widget.me.avatar, widget.me.prenom, theme, headingHome: _meHeadingHome),
                      ),
                    if (partnerPoint != null)
                      Marker(
                        point: partnerPoint,
                        width: 48,
                        height: 56,
                        child: _mapAvatar(widget.partner?.avatar, widget.partner?.prenom ?? '', theme, headingHome: _partnerHeadingHome),
                      ),
                  ],
                ),
              ],
            ),
            // Voile léger en bas pour que la pastille de distance reste
            // lisible quel que soit le fond de carte en dessous (route,
            // eau, végétation...).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    widget.distanceKm != null
                        ? '${widget.formatDistance(widget.distanceKm!)} vous séparent'
                        : "En attente de la position de ${widget.partner?.prenom ?? 'ton binôme'}",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _mapAvatar(String? avatarUrl, String prenom, dynamic theme, {bool headingHome = false}) {
    final initial = prenom.isNotEmpty ? prenom[0].toUpperCase() : '?';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: theme.primary,
            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(initial, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))
                : null,
          ),
        ),
        // "En route vers la maison" (voir demande utilisateur) — petit
        // badge sous l'avatar plutôt qu'un texte flottant, pour rester
        // lisible même à plusieurs sur la même carte.
        if (headingHome)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999)),
            child: const Text('🏠', style: TextStyle(fontSize: 11)),
          ),
      ],
    );
  }

  Widget _homeMarker(dynamic theme) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.secondary,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: const Icon(Icons.home_rounded, color: Colors.white, size: 20),
    );
  }
}

/// Interpolation linéaire simple entre deux coordonnées — suffisant pour
/// l'écart d'un déplacement réel (jamais un saut à l'autre bout du monde),
/// pas besoin d'une interpolation de grand cercle ici.
class _LatLngTween extends Tween<latlong.LatLng> {
  _LatLngTween({required latlong.LatLng super.begin, required latlong.LatLng super.end});

  @override
  latlong.LatLng lerp(double t) => latlong.LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}
