import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../core/api_client.dart';
import '../../core/live_location_service.dart';
import '../../core/realtime_client.dart';
import '../../models/app_user.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'box_scope.dart';
import 'box_service.dart';

/// "Notre distance" (voir demande utilisateur) — partage PONCTUEL de
/// position, JAMAIS un suivi continu : un seul relevé GPS par tap sur
/// "Partager ma position", aucune tâche de fond. Pas de vraie carte
/// interactive (choix validé avec l'utilisateur, évite Google Maps/clé
/// API) — juste le chiffre et un visuel stylisé.
class DistanceScreen extends StatefulWidget {
  final AppUser user;

  const DistanceScreen({super.key, required this.user});

  @override
  State<DistanceScreen> createState() => _DistanceScreenState();
}

class _DistanceScreenState extends State<DistanceScreen> with SingleTickerProviderStateMixin {
  bool _sharing = false;
  String? _error;
  String? _boxId;
  bool _liveSharingBusy = false;
  bool _refreshing = false;
  // Anime l'icône de rafraîchissement pendant l'appel (voir demande
  // utilisateur : "ça doit faire une rotation... pour dire que l'action
  // s'est bien passée") — tourne en continu tant que ça charge, s'arrête
  // net dès que la réponse arrive.
  late final AnimationController _refreshIconController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // BoxScope a besoin du context déjà rattaché à l'arbre — jamais dans
    // initState() (voir demande utilisateur, exception Flutter :
    // "dependOnInheritedWidgetOfExactType<BoxScope>()... called before
    // initState() completed"), même principe que TimelineScreen. Mise à
    // jour en direct si le/la partenaire partage sa position pendant qu'on
    // est déjà sur cet écran (voir BoxLocationShared côté backend) — un
    // simple refetch complet, même principe que BoxWaitingScreen.
    final boxId = BoxScope.of(context).currentBox?.id;
    if (boxId != null && boxId != _boxId) {
      if (_boxId != null) {
        RealtimeClient.instance.unsubscribeFromBox(_boxId!, onEvent: _onRealtimeEvent);
      }
      _boxId = boxId;
      RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
    }
  }

  @override
  void dispose() {
    if (_boxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_boxId!, onEvent: _onRealtimeEvent);
    }
    _refreshIconController.dispose();
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'BoxLocationShared') return;
    BoxService.instance.fetchCurrent();
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
        // Largeur dispo pour la rangée d'avatars, calculée à la main plutôt
        // qu'avec un LayoutBuilder (voir _DistanceAvatars — un LayoutBuilder
        // ne peut PAS vivre sous un IntrinsicHeight, exception Flutter :
        // "does not support returning intrinsic dimensions", ce qui cassait
        // le rendu de tout l'écran) : 24 de chaque côté (SingleChildScrollView)
        // + 20 de chaque côté (padding de la carte dégradée) = 88 au total.
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
          body: ThemedBackground(
            child: SafeArea(
              // Tirer-pour-rafraîchir (voir demande utilisateur, _refresh)
              // — RefreshIndicator exige un descendant scrollable ; le
              // LayoutBuilder+ConstrainedBox+IntrinsicHeight ci-dessous
              // reproduit exactement l'ancien centrage par Spacer tout en
              // rendant le contenu défilable/rafraîchissable.
              child: RefreshIndicator(
                color: theme.primary,
                backgroundColor: theme.surface,
                onRefresh: _refresh,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              const Spacer(),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        children: [
                          // Deux avatars côte à côte (PAS superposés — voir
                          // demande utilisateur : le petit badge du
                          // Dashboard, conçu tout petit avec un
                          // chevauchement fixe, devenait "collé" une fois
                          // agrandi ici) reliés par un cœur, dans l'esprit
                          // de la capture de référence fournie.
                          _DistanceAvatars(me: widget.user, partner: partner, distanceKm: distance, maxWidth: avatarsMaxWidth),
                          const SizedBox(height: 20),
                          Text(
                            distance != null ? _formatDistance(distance) : 'Position non partagée',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            distance != null ? 'vous séparent en ce moment' : "l'un de vous deux n'a pas encore partagé la sienne",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (myLocation != null || partnerLocation != null)
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
                    const Spacer(),
                    // Interrupteur "partage en direct" (voir demande
                    // utilisateur : "dès que l'application est ouverte") —
                    // DÉSACTIVÉ par défaut, jamais en arrière-plan (voir
                    // LiveLocationService), le partage ponctuel ci-dessous
                    // reste disponible que l'interrupteur soit activé ou non.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: LiveLocationService.instance.enabled,
                        onChanged: _liveSharingBusy ? null : _onToggleLiveSharing,
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
                    // ce bouton devient l'action inverse (couper le
                    // partage) plutôt qu'un relevé ponctuel redondant avec
                    // ce que le flux en direct fait déjà tout seul.
                    if (LiveLocationService.instance.enabled)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _liveSharingBusy ? null : () => _onToggleLiveSharing(false),
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
                          onPressed: _sharing ? null : _shareLocation,
                          icon: _sharing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.my_location_rounded),
                          label: Text(_sharing ? 'Localisation...' : 'Partager ma position'),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      // Honnête selon l'état réel de l'interrupteur
                      // ci-dessus — jamais "jamais de suivi" affiché alors
                      // que le partage en direct est actif.
                      LiveLocationService.instance.enabled
                          ? 'Partage en direct actif tant que l\'app reste ouverte.'
                          : 'Jamais de suivi en continu — juste un relevé ponctuel à chaque tap.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted),
                    ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
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
