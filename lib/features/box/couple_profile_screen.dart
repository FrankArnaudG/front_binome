import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../auth/auth_service.dart';
import '../games/widgets/couple_stats_card.dart';
import '../home/widgets/dark_day_counter_card.dart';
import '../settings/widgets/box_management_card.dart';
import 'box_scope.dart';

/// Profil commun du couple — ouvert au tap sur les deux avatars (voir
/// [CoupleAvatarsBadge]) dans le Dashboard et l'en-tête de conversation.
/// Réunit ce qui appartient au COUPLE plutôt qu'à une seule personne (déjà
/// dans l'onglet Profil individuel) : depuis quand, le score de complicité
/// (voir [CoupleStatsCard]), le code de Box (voir [BoxManagementCard],
/// réutilisée telle quelle pour garder le même partage que les Paramètres)
/// — aucun nouvel endpoint nécessaire, tout existait déjà.
class CoupleProfileScreen extends StatefulWidget {
  final AppUser user;

  const CoupleProfileScreen({super.key, required this.user});

  @override
  State<CoupleProfileScreen> createState() => _CoupleProfileScreenState();
}

class _CoupleProfileScreenState extends State<CoupleProfileScreen> {
  // Incrémenté à chaque tirer-pour-actualiser : sert de Key à
  // CoupleStatsCard pour forcer son remontage (et donc son refetch, qui
  // gère son propre chargement) sans dupliquer sa logique interne ici.
  int _refreshTick = 0;

  // Copie locale modifiable : widget.user est une valeur figée passée par
  // l'écran parent (Dashboard/conversation), pas une source réactive comme
  // BoxScope. Éditer les petits noms ici doit se refléter immédiatement à
  // l'écran sans attendre un remontage venu d'ailleurs.
  late AppUser _user = widget.user;

  // Même mécanisme de présence que CoupleAvatarsBadge/DashboardTab (voir
  // demande utilisateur : le cœur ici était purement décoratif, jamais vert
  // quand le binôme est en ligne comme sur le Dashboard).
  String? _subscribedBoxId;
  String? _partnerId;
  bool _partnerPresent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribePresence());
  }

  void _subscribePresence() {
    final box = BoxScope.of(context).currentBox;
    if (box == null || !mounted) return;
    _subscribedBoxId = box.id;
    _partnerId = box.partnerOf(_user.id)?.id;
    RealtimeClient.instance.subscribeToBox(box.id, onEvent: _onNoOpEvent, onPresenceChange: _onPresenceChange);
  }

  // Cet écran n'a besoin que de la présence, jamais des événements
  // applicatifs du canal — une méthode d'instance stable (contrairement à
  // une closure anonyme) pour que [dispose] puisse retirer EXACTEMENT ce
  // même écouteur plutôt que d'en laisser un fantôme enregistré pour rien.
  void _onNoOpEvent(RealtimeEvent event) {}

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    final present = _partnerId != null && memberIds.contains(_partnerId);
    if (present != _partnerPresent) setState(() => _partnerPresent = present);
  }

  @override
  void dispose() {
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_subscribedBoxId!, onEvent: _onNoOpEvent, onPresenceChange: _onPresenceChange);
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    await BoxScope.of(context).fetchCurrent();
    if (mounted) setState(() => _refreshTick++);
  }

  // Distinct de DarkDayCounterCard._editTogetherSince (même logique,
  // dupliquée plutôt que partagée — voir demande utilisateur : ce texte-ci
  // n'affichait jusqu'ici QUE box.pairedAt, jamais la vraie date corrigée,
  // et restait figé sans aucun moyen de l'éditer depuis cet endroit précis).
  bool _savingTogetherSince = false;

  Future<void> _editTogetherSince() async {
    final box = BoxScope.of(context).currentBox;
    if (box == null) return;
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

    setState(() => _savingTogetherSince = true);
    try {
      await boxService.updateSettings(togetherSince: picked);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _savingTogetherSince = false);
    }
  }

  /// Édition des petits noms directement depuis cet écran (déplacé
  /// depuis l'onglet Profil, voir ProfileCard) — même motif deletable-chips
  /// + champ d'ajout que l'ancien emplacement, dans une AlertDialog à
  /// état local (StatefulBuilder).
  // Même limite que côté backend (voir ProfileController::updateProfile) —
  // évite un aller-retour réseau pour se faire rejeter juste après.
  static const _maxNicknames = 3;

  Future<void> _editNicknames() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final partnerName = BoxScope.of(
      context,
    ).currentBox?.partnerOf(_user.id)?.prenom;
    var names = List.of(_user.loveName);
    final controller = TextEditingController();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Valide le texte en attente dans le champ (s'il y en a un) avant
          // de faire autre chose — sans ça, commencer à modifier une
          // deuxième pastille pendant qu'une autre était déjà en cours
          // d'édition écrasait silencieusement la première (constaté en
          // réel : "les autres noms disparaissent").
          void commitPending() {
            final value = controller.text.trim();
            if (value.isNotEmpty &&
                names.length < _maxNicknames &&
                !names.contains(value)) {
              names = [...names, value];
            }
            controller.clear();
          }

          void addName() {
            setDialogState(commitPending);
          }

          // Tap sur une pastille existante (pas sa croix) : la retire de la
          // liste et recharge son texte dans le champ pour la modifier,
          // plutôt que de devoir la supprimer puis la retaper de zéro.
          void editName(String name) {
            setDialogState(() {
              commitPending();
              names = names.where((n) => n != name).toList();
              controller.text = name;
            });
          }

          return AlertDialog(
            backgroundColor: theme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              t('nickname_dialog_title', {
                'name': partnerName ?? t('common_binome_fallback'),
              }),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.textOnBackground,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (names.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in names)
                        InputChip(
                          label: Text(
                            name,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              color: theme.textOnBackground,
                            ),
                          ),
                          backgroundColor: theme.background,
                          onPressed: () => editName(name),
                          deleteIcon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: theme.textOnBackgroundMuted,
                          ),
                          onDeleted: () => setDialogState(
                            () =>
                                names = names.where((n) => n != name).toList(),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (names.length < _maxNicknames)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          maxLength: 30,
                          style: TextStyle(color: theme.textOnBackground),
                          decoration: InputDecoration(
                            hintText: t('nickname_hint'),
                            hintStyle: TextStyle(
                              color: theme.textOnBackgroundMuted,
                            ),
                            counterText: '',
                          ),
                          onSubmitted: (_) => addName(),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.add_circle_rounded,
                          color: theme.primary,
                        ),
                        onPressed: addName,
                      ),
                    ],
                  )
                else
                  // Sans ce message, le champ disparaissait simplement une
                  // fois la limite atteinte, sans que rien n'explique
                  // pourquoi (constaté en réel).
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: theme.textOnBackgroundMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t('nickname_limit_info', {'max': '$_maxNicknames'}),
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            color: theme.textOnBackgroundMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  t('common_cancel'),
                  style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.primary),
                onPressed: () {
                  // Le nom en cours de frappe n'a pas forcément été validé
                  // via "+" avant d'enregistrer — sans ce filet, il était
                  // perdu silencieusement (constaté en réel).
                  commitPending();
                  Navigator.of(dialogContext).pop(names);
                },
                child: Text(t('common_save')),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    try {
      final updated = await AuthService.instance.updateProfile(
        loveName: result,
      );
      if (mounted) setState(() => _user = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      // Un timeout/souci réseau/format de réponse inattendu ne lève pas
      // forcément une ApiException — sans ce filet, l'échec était englouti
      // en silence : le crayon se refermait, rien ne se sauvegardait, et
      // rien n'expliquait pourquoi (constaté en réel).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleScope.of(context).t('nickname_save_error')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(_user.id);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('couple_title'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: theme.primary,
            backgroundColor: theme.surface,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Center(
                  child: Column(
                    children: [
                      // Petits noms rattachés directement à leur avatar (pas
                      // une rangée de pastilles ambiguë en dessous) — on sait
                      // immédiatement à qui appartient chacun. Un petit nom
                      // est ce qu'on DONNE à l'autre : le crayon n'apparaît
                      // donc que sur l'avatar du binôme (voir
                      // _AvatarsWithNicknames pour le détail du croisement).
                      _AvatarsWithNicknames(
                        user: _user,
                        partner: partner,
                        theme: theme,
                        partnerPresent: _partnerPresent,
                        onEditNicknamesForPartner: _editNicknames,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        partner != null
                            ? '${_user.prenom} & ${partner.prenom}'
                            : _user.prenom,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: theme.textOnBackground,
                        ),
                      ),
                      if (box != null) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _savingTogetherSince ? null : _editTogetherSince,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  // Tant que personne n'a corrigé la date (voir
                                  // Box.togetherSinceOverride), on ne montre
                                  // JAMAIS pairedAt (le jumelage technique) ici
                                  // comme s'il s'agissait de la vraie histoire
                                  // du couple — on invite plutôt à la
                                  // renseigner (voir demande utilisateur).
                                  box.togetherSinceOverride != null
                                      ? t('together_since_label', {
                                          'date': _formattedDate(box.togetherSinceOverride!, t),
                                        })
                                      : t('together_since_picker_title'),
                                  style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    color: theme.textOnBackgroundMuted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.edit_rounded, size: 13, color: theme.textOnBackgroundMuted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _SectionLabel(label: t('motto_section_label'), theme: theme),
                const SizedBox(height: 10),
                if (box != null) _MottoCard(box: box, theme: theme),
                const SizedBox(height: 28),
                _SectionLabel(label: t('history_section_label'), theme: theme),
                const SizedBox(height: 10),
                DarkDayCounterCard(box: box, alwaysShowEditControls: true, showDateEditControl: false),
                const SizedBox(height: 12),
                CoupleStatsCard(key: ValueKey('stats-$_refreshTick')),
                if (box != null) ...[
                  const SizedBox(height: 24),
                  _SectionLabel(label: t('box_section_label'), theme: theme),
                  const SizedBox(height: 10),
                  BoxManagementCard(box: box, partnerName: partner?.prenom),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formattedDate(
    DateTime dt,
    String Function(String, [Map<String, String>?]) t,
  ) {
    return '${dt.day} ${t('month_${dt.month}')} ${dt.year}';
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final ThemePalette theme;

  const _SectionLabel({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.nunito(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: theme.textOnBackgroundMuted,
      ),
    );
  }
}

class _AvatarsWithNicknames extends StatelessWidget {
  static const _onlineColor = Color(0xFF2ECC71);

  final AppUser user;
  final AppUser? partner;
  final ThemePalette theme;
  final bool partnerPresent;
  final VoidCallback onEditNicknamesForPartner;

  const _AvatarsWithNicknames({
    required this.user,
    required this.partner,
    required this.theme,
    required this.partnerPresent,
    required this.onEditNicknamesForPartner,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sous MON avatar : les petits noms que MON binôme me donne (son
        // champ loveName à lui/elle) — pas éditable depuis ici.
        _PersonColumn(
          person: user,
          nicknames: partner?.loveName ?? const [],
          background: theme.primary,
          theme: theme,
        ),
        SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.background,
                border: Border.all(color: theme.surface, width: 2),
              ),
              child: Icon(
                Icons.favorite_rounded,
                // Vert quand le binôme est en ligne — même code couleur et
                // même principe que CoupleAvatarsBadge (voir demande
                // utilisateur : ce cœur-ci était purement décoratif).
                color: partnerPresent ? _onlineColor : theme.primary,
                size: 16,
              ),
            ),
          ),
        ),
        // Sous l'avatar de MON binôme : les petits noms que JE lui donne
        // (mon propre champ loveName) — c'est ici, et seulement ici, que
        // le crayon apparaît : un petit nom est ce qu'on donne à l'autre,
        // pas ce qu'on se donne à soi-même.
        _PersonColumn(
          person: partner,
          nicknames: user.loveName,
          background: theme.secondary,
          theme: theme,
          onEditNicknames: partner != null ? onEditNicknamesForPartner : null,
        ),
      ],
    );
  }
}

class _PersonColumn extends StatelessWidget {
  final AppUser? person;
  final Color background;
  final ThemePalette theme;

  /// Passés explicitement plutôt que dérivés de `person.loveName` : un
  /// petit nom est ce que l'AUTRE personne donne, pas ce qu'on se donne à
  /// soi-même — voir [_AvatarsWithNicknames] pour le croisement source
  /// (mes noms à moi apparaissent sous l'avatar de mon binôme, pas le mien).
  final List<String> nicknames;

  /// Non-null uniquement sur l'avatar du binôme (voir
  /// [_AvatarsWithNicknames]) — le petit crayon n'apparaît jamais sur son
  /// propre avatar, dont le contenu vient de l'autre et n'est pas
  /// éditable d'ici.
  final VoidCallback? onEditNicknames;

  const _PersonColumn({
    required this.person,
    required this.nicknames,
    required this.background,
    required this.theme,
    this.onEditNicknames,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = person?.avatar;
    final initial = person != null && person!.prenom.isNotEmpty
        ? person!.prenom[0].toUpperCase()
        : '?';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 96),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.background, width: 3),
                ),
                child: CircleAvatar(
                  radius: 33,
                  backgroundColor: background,
                  backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                  child: avatar == null
                      ? Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
              if (onEditNicknames != null)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Material(
                    color: theme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onEditNicknames,
                      child: Container(
                        width: 26,
                        height: 26,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.background, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Tous les petits noms, pas seulement le premier — empilés
          // verticalement (pas de largeur pour un vrai carrousel/accordéon
          // ici) plutôt que tronqués en un seul, faute de place.
          if (nicknames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final name in nicknames)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Devise/citation du couple (voir BoxController::updateSettings) — courte
/// phrase libre et partagée, éditable par n'importe lequel des deux
/// partenaires directement depuis cet écran (pas de va-et-vient vers les
/// Paramètres, contrairement aux petits noms qui sont propres à chacun·e).
class _MottoCard extends StatefulWidget {
  final Box box;
  final ThemePalette theme;

  const _MottoCard({required this.box, required this.theme});

  @override
  State<_MottoCard> createState() => _MottoCardState();
}

class _MottoCardState extends State<_MottoCard> {
  bool _saving = false;

  Future<void> _edit() async {
    final theme = widget.theme;
    final t = LocaleScope.of(context).t;
    // Capturé avant l'await : BoxScope.of(context) après le dialogue
    // utiliserait un context potentiellement démonté (voir le lint
    // "BuildContext across async gaps") — BoxService étant un singleton,
    // le récupérer tôt ne pose aucun problème de fraîcheur des données.
    final boxService = BoxScope.of(context);
    final controller = TextEditingController(text: widget.box.motto ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          t('motto_section_label'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 100,
              maxLines: 2,
              style: GoogleFonts.nunito(color: theme.textOnBackground),
              decoration: InputDecoration(
                hintText: t('motto_hint'),
                hintStyle: GoogleFonts.nunito(
                  color: theme.textOnBackgroundMuted,
                ),
              ),
            ),
            // Un exemple qui reste visible même une fois qu'on a commencé à
            // écrire (contrairement au hintText, qui disparaît) — pour
            // vraiment inspirer plutôt que juste illustrer le champ vide.
            const SizedBox(height: 6),
            Text(
              t('motto_example'),
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.textOnBackgroundMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              t('common_cancel'),
              style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.primary),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(t('common_save')),
          ),
        ],
      ),
    );

    if (result == null) return;
    setState(() => _saving = true);
    try {
      await boxService.updateSettings(motto: result);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final t = LocaleScope.of(context).t;
    final motto = widget.box.motto;

    if (motto == null || motto.isEmpty) {
      return Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _saving ? null : _edit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primary,
                        ),
                      )
                    : Icon(Icons.add_rounded, size: 18, color: theme.primary),
                const SizedBox(width: 8),
                Text(
                  t('motto_add_button'),
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _saving ? null : _edit,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.format_quote_rounded,
                color: theme.primary.withValues(alpha: 0.5),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  motto,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: theme.textOnBackground,
                  ),
                ),
              ),
              _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.textOnBackgroundMuted,
                      ),
                    )
                  : Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: theme.textOnBackgroundMuted,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
