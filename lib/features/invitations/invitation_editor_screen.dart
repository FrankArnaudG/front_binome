import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primary_button.dart';
import 'invitation_catalogue_screen.dart' show openExternalLink;
import 'invitation_service.dart';
import 'models/invitation_models.dart';

/// Éditeur d'une invitation — 6 onglets suivant les blocs retenus pour la
/// Phase 1 du cahier des charges (couverture/familles/histoire fusionnés
/// dans "Infos" et "Famille & histoire", cérémonies+lieux fusionnés dans
/// un seul bloc, tenue, galerie, RSVP). Pas de bloc musique/livre d'or
/// (Phase 2) ni cadeaux/argent (jamais — consigne explicite et permanente).
class InvitationEditorScreen extends StatefulWidget {
  final String invitationId;

  const InvitationEditorScreen({super.key, required this.invitationId});

  @override
  State<InvitationEditorScreen> createState() => _InvitationEditorScreenState();
}

class _InvitationEditorScreenState extends State<InvitationEditorScreen> {
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  Invitation? _invitation;

  final _partnerOneCtrl = TextEditingController();
  final _partnerTwoCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _introCtrl = TextEditingController();
  DateTime? _eventDate;

  final _familiesLinesCtrl = TextEditingController();
  final _familiesFormulaCtrl = TextEditingController();
  final _customEventTypeCtrl = TextEditingController();
  String? _eventType;
  final _storyTitleCtrl = TextEditingController();
  final _storyTextCtrl = TextEditingController();
  final _quoteTitleCtrl = TextEditingController();
  final _storyQuoteCtrl = TextEditingController();

  final _dressTitleCtrl = TextEditingController();
  final _dressDescriptionCtrl = TextEditingController();
  final _dressColorsCtrl = TextEditingController();
  final _dressInstructionsCtrl = TextEditingController();
  // Voir demande utilisateur : jusqu'à 3 contacts (appel ou WhatsApp),
  // entièrement optionnel — liste simple, pas de TextEditingController ici
  // (gérés localement par _DressContactsEditor).
  List<Map<String, String>> _dressContacts = [];

  DateTime? _rsvpDeadline;
  final _rsvpMaxCompanionsCtrl = TextEditingController(text: '2');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partnerOneCtrl.dispose();
    _partnerTwoCtrl.dispose();
    _cityCtrl.dispose();
    _introCtrl.dispose();
    _familiesLinesCtrl.dispose();
    _familiesFormulaCtrl.dispose();
    _customEventTypeCtrl.dispose();
    _storyTitleCtrl.dispose();
    _storyTextCtrl.dispose();
    _quoteTitleCtrl.dispose();
    _storyQuoteCtrl.dispose();
    _dressTitleCtrl.dispose();
    _dressDescriptionCtrl.dispose();
    _dressColorsCtrl.dispose();
    _dressInstructionsCtrl.dispose();
    _rsvpMaxCompanionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invitation = await InvitationService.instance.fetchInvitation(widget.invitationId);
      if (!mounted) return;
      _applyToControllers(invitation);
      setState(() {
        _invitation = invitation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _applyToControllers(Invitation invitation) {
    _partnerOneCtrl.text = invitation.partnerOneName ?? '';
    _partnerTwoCtrl.text = invitation.partnerTwoName ?? '';
    _cityCtrl.text = invitation.eventCity ?? '';
    _introCtrl.text = invitation.introText ?? '';
    _eventDate = invitation.eventDate != null ? DateTime.tryParse(invitation.eventDate!) : null;

    final linesRaw = invitation.families['lines'];
    _familiesLinesCtrl.text = linesRaw is List ? linesRaw.join('\n') : '';
    _familiesFormulaCtrl.text = invitation.families['formula'] as String? ?? '';
    _eventType = invitation.families['event_type'] as String?;
    _customEventTypeCtrl.text = invitation.families['custom_event_type'] as String? ?? '';

    _storyTitleCtrl.text = invitation.story['title'] as String? ?? '';
    _storyTextCtrl.text = invitation.story['text'] as String? ?? '';
    _quoteTitleCtrl.text = invitation.story['quote_title'] as String? ?? '';
    _storyQuoteCtrl.text = invitation.story['quote'] as String? ?? '';

    _dressTitleCtrl.text = invitation.dressCode['title'] as String? ?? '';
    _dressDescriptionCtrl.text = invitation.dressCode['description'] as String? ?? '';
    final colorsRaw = invitation.dressCode['colors'];
    _dressColorsCtrl.text = colorsRaw is List ? colorsRaw.join(', ') : '';
    _dressInstructionsCtrl.text = invitation.dressCode['instructions'] as String? ?? '';
    final contactsRaw = invitation.dressCode['contacts'];
    _dressContacts = contactsRaw is List
        ? contactsRaw.whereType<Map>().map((c) => {
              'type': (c['type'] as String?) ?? 'appel',
              'number': (c['number'] as String?) ?? '',
            }).toList()
        : [];

    final deadlineRaw = invitation.rsvpSettings['deadline'] as String?;
    _rsvpDeadline = deadlineRaw != null ? DateTime.tryParse(deadlineRaw) : null;
    _rsvpMaxCompanionsCtrl.text = '${invitation.rsvpSettings['max_companions'] ?? 2}';
  }

  String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final lines = _familiesLinesCtrl.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final colors = _dressColorsCtrl.text.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).take(3).toList();
      final contacts = _dressContacts.where((c) => (c['number'] ?? '').trim().isNotEmpty).take(3).toList();

      final updated = await InvitationService.instance.updateInvitation(widget.invitationId, {
        'partner_one_name': _partnerOneCtrl.text.trim(),
        'partner_two_name': _partnerTwoCtrl.text.trim(),
        'event_city': _cityCtrl.text.trim(),
        'intro_text': _introCtrl.text.trim(),
        'event_date': _eventDate != null ? _isoDate(_eventDate!) : null,
        'families': {
          'lines': lines,
          'formula': _familiesFormulaCtrl.text.trim(),
          'event_type': _eventType,
          'custom_event_type': _customEventTypeCtrl.text.trim(),
        },
        'story': {
          'title': _storyTitleCtrl.text.trim(),
          'text': _storyTextCtrl.text.trim(),
          'quote_title': _quoteTitleCtrl.text.trim(),
          'quote': _storyQuoteCtrl.text.trim(),
        },
        'dress_code': {
          'title': _dressTitleCtrl.text.trim(),
          'description': _dressDescriptionCtrl.text.trim(),
          'colors': colors,
          'instructions': _dressInstructionsCtrl.text.trim(),
          'contacts': contacts,
        },
        'rsvp_settings': {
          'deadline': _rsvpDeadline != null ? _isoDate(_rsvpDeadline!) : null,
          'max_companions': int.tryParse(_rsvpMaxCompanionsCtrl.text.trim()) ?? 2,
        },
      });
      if (!mounted) return;
      setState(() => _invitation = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brouillon enregistré.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preview() async {
    await _save();
    if (!mounted) return;
    try {
      final url = await InvitationService.instance.requestPreviewUrl(widget.invitationId);
      await openExternalLink(url);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _publish() async {
    await _save();
    if (!mounted) return;
    try {
      final (invitation, publicUrl) = await InvitationService.instance.publish(widget.invitationId);
      if (!mounted) return;
      setState(() => _invitation = invitation);
      await _showPublishedSheet(publicUrl);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showPublishedSheet(String publicUrl) async {
    if (!mounted) return;
    final theme = ThemeScope.paletteOf(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invitation publiée 🎉', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, fontSize: 20, color: theme.textOnBackground)),
              const SizedBox(height: 8),
              Text(publicUrl, style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Partager le lien',
                icon: Icons.share_rounded,
                onPressed: () => Share.share(publicUrl),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => openExternalLink(publicUrl),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Voir la page'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSuspend() async {
    final invitation = _invitation;
    if (invitation == null) return;
    try {
      final updated = invitation.status == 'suspended'
          ? await InvitationService.instance.resume(widget.invitationId)
          : await InvitationService.instance.suspend(widget.invitationId);
      if (!mounted) return;
      setState(() => _invitation = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette invitation ?'),
        content: const Text('Cette action est définitive — le lien public cessera de fonctionner.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await InvitationService.instance.deleteInvitation(widget.invitationId);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    if (_loading) {
      return Scaffold(backgroundColor: theme.background, body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _invitation == null) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(backgroundColor: theme.background),
        body: EmptyState(
          icon: Icons.wifi_off_rounded,
          message: _error is ApiException ? (_error as ApiException).message : 'Impossible de charger cette invitation.',
          actionLabel: 'Réessayer',
          onAction: _load,
        ),
      );
    }

    final invitation = _invitation!;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          elevation: 0,
          title: Text(
            [invitation.partnerOneName, invitation.partnerTwoName].where((n) => n != null && n.isNotEmpty).join(' & ').isEmpty
                ? 'Nouvelle invitation'
                : [invitation.partnerOneName, invitation.partnerTwoName].where((n) => n != null && n.isNotEmpty).join(' & '),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: theme.textOnBackground),
          ),
          iconTheme: IconThemeData(color: theme.textOnBackground),
          actions: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: theme.textOnBackground),
              onSelected: (value) {
                if (value == 'suspend') _toggleSuspend();
                if (value == 'delete') _delete();
              },
              itemBuilder: (context) => [
                if (invitation.status == 'published' || invitation.status == 'suspended')
                  PopupMenuItem(value: 'suspend', child: Text(invitation.status == 'suspended' ? 'Reprendre la diffusion' : 'Suspendre')),
                const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: theme.primary,
            unselectedLabelColor: theme.textOnBackgroundMuted,
            indicatorColor: theme.primary,
            tabs: const [
              Tab(text: 'Infos'),
              Tab(text: 'Famille'),
              Tab(text: 'Histoire'),
              Tab(text: 'Cérémonies'),
              Tab(text: 'Tenue'),
              Tab(text: 'Galerie'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InfosTab(
              theme: theme,
              invitation: invitation,
              partnerOneCtrl: _partnerOneCtrl,
              partnerTwoCtrl: _partnerTwoCtrl,
              cityCtrl: _cityCtrl,
              introCtrl: _introCtrl,
              eventDate: _eventDate,
              onPickDate: (d) => setState(() => _eventDate = d),
              rsvpDeadline: _rsvpDeadline,
              onPickRsvpDeadline: (d) => setState(() => _rsvpDeadline = d),
              rsvpMaxCompanionsCtrl: _rsvpMaxCompanionsCtrl,
              onMediaChanged: _load,
            ),
            _FamiliesTab(
              theme: theme,
              linesCtrl: _familiesLinesCtrl,
              formulaCtrl: _familiesFormulaCtrl,
              customEventTypeCtrl: _customEventTypeCtrl,
              eventType: _eventType,
              onEventTypeChanged: (type, phrase) => setState(() {
                _eventType = type;
                _familiesFormulaCtrl.text = phrase;
              }),
            ),
            _StoryTab(
              theme: theme,
              invitation: invitation,
              titleCtrl: _storyTitleCtrl,
              textCtrl: _storyTextCtrl,
              quoteTitleCtrl: _quoteTitleCtrl,
              quoteCtrl: _storyQuoteCtrl,
              onMediaChanged: _load,
            ),
            _CeremoniesTab(theme: theme, invitation: invitation, onChanged: _load),
            _DressCodeTab(
              theme: theme,
              invitation: invitation,
              titleCtrl: _dressTitleCtrl,
              descriptionCtrl: _dressDescriptionCtrl,
              colorsCtrl: _dressColorsCtrl,
              instructionsCtrl: _dressInstructionsCtrl,
              contacts: _dressContacts,
              onContactsChanged: (updated) => _dressContacts = updated,
              onMediaChanged: _load,
            ),
            _GalleryTab(theme: theme, invitation: invitation, onChanged: _load),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _preview,
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('Prévisualiser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: invitation.isPublished ? 'Mettre à jour' : 'Publier',
                    loading: _saving,
                    onPressed: invitation.isPublished ? _save : _publish,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final dynamic theme;
  final ValueChanged<String>? onChanged;

  const _SectionField({required this.label, required this.controller, required this.theme, this.maxLines = 1, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: GoogleFonts.nunito(color: theme.textOnBackground),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
          filled: true,
          fillColor: theme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _InfosTab extends StatelessWidget {
  final dynamic theme;
  final Invitation invitation;
  final TextEditingController partnerOneCtrl;
  final TextEditingController partnerTwoCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController introCtrl;
  final DateTime? eventDate;
  final void Function(DateTime) onPickDate;
  final DateTime? rsvpDeadline;
  final void Function(DateTime) onPickRsvpDeadline;
  final TextEditingController rsvpMaxCompanionsCtrl;
  final VoidCallback onMediaChanged;

  const _InfosTab({
    required this.theme,
    required this.invitation,
    required this.partnerOneCtrl,
    required this.partnerTwoCtrl,
    required this.cityCtrl,
    required this.introCtrl,
    required this.eventDate,
    required this.onPickDate,
    required this.rsvpDeadline,
    required this.onPickRsvpDeadline,
    required this.rsvpMaxCompanionsCtrl,
    required this.onMediaChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CoverPresetPicker(theme: theme, invitation: invitation, onChanged: onMediaChanged),
        const SizedBox(height: 16),
        _SectionField(label: 'Prénom 1', controller: partnerOneCtrl, theme: theme),
        _SectionField(label: 'Prénom 2', controller: partnerTwoCtrl, theme: theme),
        _DatePickerField(label: 'Date du mariage', value: eventDate, theme: theme, onChanged: onPickDate),
        const SizedBox(height: 14),
        _SectionField(label: 'Ville', controller: cityCtrl, theme: theme),
        _SectionField(label: "Texte d'introduction", controller: introCtrl, theme: theme, maxLines: 2),
        const SizedBox(height: 10),
        Text('Confirmation de présence (RSVP)', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground)),
        const SizedBox(height: 10),
        _DatePickerField(label: 'Date limite de réponse', value: rsvpDeadline, theme: theme, onChanged: onPickRsvpDeadline),
        const SizedBox(height: 14),
        _SectionField(label: "Nombre d'accompagnants maximum", controller: rsvpMaxCompanionsCtrl, theme: theme),
      ],
    );
  }
}

/// Type d'événement -> phrase suggérée pour la formule des familles (voir
/// demande utilisateur : "déterminer s'il s'agit d'un mariage, mariage
/// traditionnel...") — pré-remplit `formulaCtrl` au choix, reste modifiable
/// ensuite comme n'importe quel autre champ.
const Map<String, String> _eventTypePhrases = {
  'mariage': "ont l'honneur de vous convier au mariage de",
  'mariage_traditionnel': "ont l'honneur de vous convier au mariage traditionnel de",
  'fiancailles': "ont l'honneur de vous convier aux fiançailles de",
  'autre': "ont l'honneur de vous convier à la cérémonie de",
};
const Map<String, String> _eventTypeLabels = {
  'mariage': 'Mariage',
  'mariage_traditionnel': 'Mariage traditionnel',
  'fiancailles': 'Fiançailles',
  'autre': 'Autre',
};

class _FamiliesTab extends StatelessWidget {
  final dynamic theme;
  final TextEditingController linesCtrl;
  final TextEditingController formulaCtrl;
  final TextEditingController customEventTypeCtrl;
  final String? eventType;
  final void Function(String type, String phrase) onEventTypeChanged;

  const _FamiliesTab({
    required this.theme,
    required this.linesCtrl,
    required this.formulaCtrl,
    required this.customEventTypeCtrl,
    required this.eventType,
    required this.onEventTypeChanged,
  });

  /// Reconstruit la formule à partir du nom de type saisi — jamais éditée
  /// directement (voir demande utilisateur : "la formule est standard à
  /// tous et non modifiable"), seul ce nom l'est.
  void _applyCustomType(String typeName) {
    final trimmed = typeName.trim();
    formulaCtrl.text = trimmed.isEmpty ? '' : "ont l'honneur de vous convier au $trimmed de";
  }

  @override
  Widget build(BuildContext context) {
    final isCustomType = eventType == 'autre';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Une ligne par famille (ex. "Les familles Ouedraogo et Traoré").',
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 10),
        _SectionField(label: 'Familles', controller: linesCtrl, theme: theme, maxLines: 2),
        _DropdownField<String>(
          theme: theme,
          label: "Type d'événement",
          value: eventType,
          items: _eventTypeLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (type) {
            if (type == null) return;
            // La formule est toujours un modèle fixe, jamais éditable
            // directement — pour "Autre" elle se construit à partir du nom
            // de type saisi juste en dessous (voir _applyCustomType) —
            // calculée depuis le nom déjà saisi, jamais la formule
            // précédente (qui viendrait d'un autre type).
            final customName = customEventTypeCtrl.text.trim();
            final autrePhrase = customName.isEmpty ? '' : "ont l'honneur de vous convier au $customName de";
            onEventTypeChanged(type, type == 'autre' ? autrePhrase : (_eventTypePhrases[type] ?? ''));
          },
        ),
        if (isCustomType) ...[
          const SizedBox(height: 14),
          _SectionField(
            label: "Préciser le type d'événement (ex. baptême, anniversaire de mariage)",
            controller: customEventTypeCtrl,
            theme: theme,
            onChanged: _applyCustomType,
          ),
        ],
        const SizedBox(height: 16),
        Text('Aperçu', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackgroundMuted)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: Listenable.merge([linesCtrl, formulaCtrl]),
          builder: (context, _) {
            final lines = linesCtrl.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
            final formula = formulaCtrl.text.trim();
            if (lines.isEmpty && formula.isEmpty) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final line in lines)
                    Text(
                      line,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textOnBackground, letterSpacing: 0.5),
                    ),
                  if (formula.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      formula,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 13, fontStyle: FontStyle.italic, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StoryTab extends StatefulWidget {
  final dynamic theme;
  final Invitation invitation;
  final TextEditingController titleCtrl;
  final TextEditingController textCtrl;
  final TextEditingController quoteTitleCtrl;
  final TextEditingController quoteCtrl;
  final VoidCallback onMediaChanged;

  const _StoryTab({
    required this.theme,
    required this.invitation,
    required this.titleCtrl,
    required this.textCtrl,
    required this.quoteTitleCtrl,
    required this.quoteCtrl,
    required this.onMediaChanged,
  });

  @override
  State<_StoryTab> createState() => _StoryTabState();
}

class _StoryTabState extends State<_StoryTab> {
  List<RomanticCategory> _categories = [];
  List<RomanticMessage> _messages = [];
  bool _loadingMessages = true;
  String? _selectedCategory;
  int? _selectedMessageId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final (categories, messages) = await InvitationService.instance.fetchRomanticMessages();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _messages = messages;
        _loadingMessages = false;
      });
    } catch (_) {
      // Best effort : la bibliothèque prédéfinie est un confort, pas un
      // blocage — les champs titre/message restent librement éditables
      // même si ce chargement échoue (pas de connexion, etc.).
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _applyPreset(RomanticMessage preset) {
    widget.quoteTitleCtrl.text = preset.title;
    widget.quoteCtrl.text = preset.message;
    setState(() => _selectedMessageId = preset.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final storyPhotos = widget.invitation.media.where((m) => m.blockKey == 'story').toList();
    final messagesInCategory = _selectedCategory == null ? <RomanticMessage>[] : _messages.where((m) => m.category == _selectedCategory).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionField(label: 'Titre', controller: widget.titleCtrl, theme: theme),
        _SectionField(label: 'Notre histoire', controller: widget.textCtrl, theme: theme, maxLines: 5),
        const SizedBox(height: 8),
        Text('Photos de notre histoire', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground)),
        const SizedBox(height: 10),
        _GalleryGrid(theme: theme, invitationId: widget.invitation.id, blockKey: 'story', items: storyPhotos, onChanged: widget.onMediaChanged),
        const SizedBox(height: 24),
        Text('Message romantique', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground)),
        const SizedBox(height: 4),
        Text(
          'Choisis un texte prédéfini comme base, puis modifie-le librement.',
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 12),
        if (_loadingMessages)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator()))
        else if (_categories.isNotEmpty) ...[
          _DropdownField<String>(
            theme: theme,
            label: 'Catégorie',
            value: _selectedCategory,
            items: _categories.map((c) => DropdownMenuItem(value: c.key, child: Text(c.label))).toList(),
            onChanged: (v) => setState(() {
              _selectedCategory = v;
              _selectedMessageId = null;
            }),
          ),
          const SizedBox(height: 14),
          if (_selectedCategory != null)
            _DropdownField<int>(
              theme: theme,
              label: 'Choisir un texte prédéfini',
              value: _selectedMessageId,
              items: messagesInCategory.map((m) => DropdownMenuItem(value: m.id, child: Text(m.title, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (id) {
                final preset = messagesInCategory.firstWhere((m) => m.id == id);
                _applyPreset(preset);
              },
            ),
          const SizedBox(height: 14),
        ],
        _SectionField(label: 'Titre personnalisable', controller: widget.quoteTitleCtrl, theme: theme),
        _SectionField(label: 'Message personnalisable', controller: widget.quoteCtrl, theme: theme, maxLines: 4),
        const SizedBox(height: 12),
        Text('Aperçu', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackgroundMuted)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: Listenable.merge([widget.quoteTitleCtrl, widget.quoteCtrl]),
          builder: (context, _) {
            if (widget.quoteCtrl.text.trim().isEmpty) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF681D32), borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('✦ ✦ ✦', style: TextStyle(color: Color(0xFFC5A05A))),
                  if (widget.quoteTitleCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.quoteTitleCtrl.text.trim(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(color: Colors.white, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, fontSize: 18),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    widget.quoteCtrl.text.trim(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final dynamic theme;
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({required this.theme, required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, labelStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted), border: InputBorder.none),
          style: GoogleFonts.nunito(color: theme.textOnBackground, fontSize: 14),
          dropdownColor: theme.surface,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DressCodeTab extends StatelessWidget {
  final dynamic theme;
  final Invitation invitation;
  final TextEditingController titleCtrl;
  final TextEditingController descriptionCtrl;
  final TextEditingController colorsCtrl;
  final TextEditingController instructionsCtrl;
  final List<Map<String, String>> contacts;
  final ValueChanged<List<Map<String, String>>> onContactsChanged;
  final VoidCallback onMediaChanged;

  const _DressCodeTab({
    required this.theme,
    required this.invitation,
    required this.titleCtrl,
    required this.descriptionCtrl,
    required this.colorsCtrl,
    required this.instructionsCtrl,
    required this.contacts,
    required this.onContactsChanged,
    required this.onMediaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final photos = invitation.media.where((m) => m.blockKey == 'dress_code').toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionField(label: 'Titre', controller: titleCtrl, theme: theme),
        _SectionField(label: 'Description', controller: descriptionCtrl, theme: theme, maxLines: 3),
        _SectionField(label: 'Couleurs (3 maximum, codes hex séparés par une virgule, ex. #681D32, #C5A05A)', controller: colorsCtrl, theme: theme),
        _SectionField(label: 'Instructions', controller: instructionsCtrl, theme: theme, maxLines: 2),
        const SizedBox(height: 16),
        Text('Photos (3 maximum, compressées automatiquement)', style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
        const SizedBox(height: 6),
        _GalleryGrid(
          theme: theme,
          invitationId: invitation.id,
          blockKey: 'dress_code',
          items: photos,
          maxItems: 3,
          onChanged: onMediaChanged,
        ),
        const SizedBox(height: 20),
        Text('Contact pour le pagne (optionnel, 3 maximum)', style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
        const SizedBox(height: 6),
        _DressContactsEditor(theme: theme, contacts: contacts, onChanged: onContactsChanged),
      ],
    );
  }
}

class _GalleryTab extends StatelessWidget {
  final dynamic theme;
  final Invitation invitation;
  final VoidCallback onChanged;

  const _GalleryTab({required this.theme, required this.invitation, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final photos = invitation.media.where((m) => m.blockKey == 'gallery').toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "Jusqu'à 30 photos — elles apparaissent dans le bloc \"Nos photos\" de l'invitation.",
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 12),
        _GalleryGrid(theme: theme, invitationId: invitation.id, blockKey: 'gallery', items: photos, onChanged: onChanged),
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final dynamic theme;
  final void Function(DateTime) onChanged;

  const _DatePickerField({required this.label, required this.value, required this.theme, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now().add(const Duration(days: 60)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 18, color: theme.textOnBackgroundMuted),
            const SizedBox(width: 10),
            Text(
              value != null ? '${value!.day}/${value!.month}/${value!.year}' : label,
              style: GoogleFonts.nunito(color: value != null ? theme.textOnBackground : theme.textOnBackgroundMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ornements embarqués dans l'app (voir pubspec.yaml `assets:` et
/// assets/invitations/heritage_royal/) — mêmes clés ('frame'/'frame_alt')
/// que côté serveur (voir InvitationTemplate::themeAssetUrls), stockées
/// séparément pour que l'éditeur affiche ces vignettes sans aller sur le
/// réseau (voir demande utilisateur : "tout doit se faire côté
/// application, image stockée côté app"). Un modèle absent de cette carte
/// retombe sur les URLs réseau du serveur (themeAssetUrls).
const Map<String, Map<String, String>> _bundledCoverPresets = {
  'heritage_royal': {
    'frame': 'assets/invitations/heritage_royal/frame.webp',
    'frame_alt': 'assets/invitations/heritage_royal/frame_alt.webp',
  },
};

/// Choix de la couverture dans une liste PRÉDÉFINIE d'ornements du modèle
/// (voir InvitationTemplate.themeAssetUrls) — jamais un upload libre depuis
/// la galerie (voir demande utilisateur explicite et répétée). Enregistre
/// directement au tap, comme un réglage plutôt qu'un champ de texte.
class _CoverPresetPicker extends StatefulWidget {
  final dynamic theme;
  final Invitation invitation;
  final VoidCallback onChanged;

  const _CoverPresetPicker({required this.theme, required this.invitation, required this.onChanged});

  @override
  State<_CoverPresetPicker> createState() => _CoverPresetPickerState();
}

class _CoverPresetPickerState extends State<_CoverPresetPicker> {
  bool _saving = false;

  Future<void> _select(String key) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await InvitationService.instance.updateInvitation(widget.invitation.id, {
        'cover_settings': {'background': key},
      });
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final templateKey = widget.invitation.template?.key;
    final bundled = templateKey != null ? _bundledCoverPresets[templateKey] : null;

    // Clé -> source d'image : un asset embarqué si connu (voir
    // _bundledCoverPresets), sinon l'URL réseau du serveur (modèle futur
    // pas encore embarqué dans l'app).
    final Map<String, String> presetSources;
    if (bundled != null) {
      presetSources = bundled;
    } else {
      final urls = widget.invitation.template?.themeAssetUrls ?? const {};
      presetSources = {
        for (final entry in urls.entries)
          if (entry.key.startsWith('ornament_frame')) entry.key.replaceFirst('ornament_', ''): entry.value,
      };
    }
    final presets = presetSources.entries.toList();
    final selected = widget.invitation.coverSettings['background'] as String? ?? 'frame';

    if (presets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Couverture', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground)),
        const SizedBox(height: 4),
        Text(
          'Choisis parmi les ornements du modèle — pas de photo personnelle pour ce bloc.',
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final entry = presets[index];
              final key = entry.key;
              final isSelected = key == selected || (key == 'frame' && selected.isEmpty);
              final isBundled = bundled != null;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _saving ? null : () => _select(key),
                child: Container(
                  width: 110,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelected ? theme.primary : Colors.transparent, width: 2),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: isBundled
                              ? Image.asset(entry.value, fit: BoxFit.contain)
                              : CachedNetworkImage(imageUrl: entry.value, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (isSelected) Icon(Icons.check_circle_rounded, size: 16, color: theme.primary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Un seul fichier à la fois (tenue/histoire/galerie) — le nouvel envoi
/// remplace l'ancien côté serveur (voir InvitationMediaController::store,
/// blocs singuliers), ce widget se contente d'afficher l'existant et de
/// proposer "Changer"/"Retirer".
class _GalleryGrid extends StatefulWidget {
  final dynamic theme;
  final String invitationId;
  final String blockKey;
  final List<InvitationMedia> items;
  final VoidCallback onChanged;
  final int? maxItems;

  const _GalleryGrid({
    required this.theme,
    required this.invitationId,
    required this.blockKey,
    required this.items,
    required this.onChanged,
    this.maxItems,
  });

  @override
  State<_GalleryGrid> createState() => _GalleryGridState();
}

/// Un ajout en cours : voir demande utilisateur — "une foi selectionner il
/// doit etre recupee et afficher dan le cadre iinstantanement [...] un
/// loadeur [...] en pourcentage. et si ca echout on clique ca poursuit".
/// Le fichier local reste affiché (aperçu immédiat) jusqu'à ce que
/// l'upload réussisse (la tuile disparaît, remplacée par l'item serveur au
/// prochain onChanged) ou échoue (icône de reprise au tap, même fichier).
class _PendingUpload {
  final File file;
  double progress;
  bool failed;
  _PendingUpload(this.file) : progress = 0, failed = false;
}

class _GalleryGridState extends State<_GalleryGrid> {
  final List<_PendingUpload> _pending = [];

  Future<void> _add() async {
    final max = widget.maxItems;
    if (max != null && widget.items.length + _pending.length >= max) return;
    // pickImage() peut lever (PlatformException, picker système absent...)
    // — DOIT être dans le try, sinon le bouton "Ajouter" ne fait plus rien
    // de visible en cas d'erreur.
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) return;
      final pending = _PendingUpload(File(picked.path));
      if (!mounted) return;
      setState(() => _pending.add(pending));
      await _upload(pending);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de choisir cette photo : $e')));
    }
  }

  Future<void> _upload(_PendingUpload pending) async {
    setState(() {
      pending.failed = false;
      pending.progress = 0;
    });
    try {
      await InvitationService.instance.uploadMedia(
        widget.invitationId,
        pending.file,
        blockKey: widget.blockKey,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => pending.progress = sent / total);
        },
      );
      if (!mounted) return;
      setState(() => _pending.remove(pending));
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => pending.failed = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => pending.failed = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec de l\'envoi : $e')));
    }
  }

  void _discardPending(_PendingUpload pending) {
    setState(() => _pending.remove(pending));
  }

  Future<void> _remove(InvitationMedia media) async {
    try {
      await InvitationService.instance.deleteMedia(widget.invitationId, media.id);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final canAdd = widget.maxItems == null || widget.items.length + _pending.length < widget.maxItems!;
    final itemsEnd = widget.items.length;
    final pendingEnd = itemsEnd + _pending.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: pendingEnd + (canAdd ? 1 : 0),
      itemBuilder: (context, index) {
        if (canAdd && index == pendingEnd) {
          return InkWell(
            onTap: _add,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Icon(Icons.add_rounded, color: theme.textOnBackgroundMuted)),
            ),
          );
        }
        if (index >= itemsEnd) {
          final pending = _pending[index - itemsEnd];
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(pending.file, fit: BoxFit.cover),
                  if (!pending.failed)
                    Container(
                      color: Colors.black38,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                value: pending.progress > 0 ? pending.progress : null,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(pending.progress * 100).round()}%',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => _upload(pending),
                      child: Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                              SizedBox(height: 2),
                              Text('Réessayer', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (pending.failed)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => _discardPending(pending),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        final item = widget.items[index];
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 1, child: CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover)),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: () => _remove(item),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Jusqu'à 3 contacts (appel ou WhatsApp) affichés en bas du bloc "Tenue"
/// sur la page publique, entièrement optionnels (voir demande utilisateur :
/// "on peu decider de ne pa mettre de numero"). Contrôleurs texte locaux
/// (comme _CeremonyFormSheet) pour ne pas perdre le focus/curseur à chaque
/// frappe — la liste n'est remontée au parent (onChanged) qu'après chaque
/// modification, jamais reconstruite depuis `widget.contacts` après coup.
class _DressContactsEditor extends StatefulWidget {
  final dynamic theme;
  final List<Map<String, String>> contacts;
  final ValueChanged<List<Map<String, String>>> onChanged;

  const _DressContactsEditor({required this.theme, required this.contacts, required this.onChanged});

  @override
  State<_DressContactsEditor> createState() => _DressContactsEditorState();
}

class _ContactRow {
  String type;
  final TextEditingController controller;
  _ContactRow({required this.type, required this.controller});
}

class _DressContactsEditorState extends State<_DressContactsEditor> {
  late List<_ContactRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.contacts
        .map((c) => _ContactRow(type: c['type'] ?? 'appel', controller: TextEditingController(text: c['number'] ?? '')))
        .toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_rows.map((r) => {'type': r.type, 'number': r.controller.text.trim()}).toList());
  }

  void _add() {
    if (_rows.length >= 3) return;
    setState(() => _rows.add(_ContactRow(type: 'appel', controller: TextEditingController())));
    _emit();
  }

  void _remove(int index) {
    setState(() {
      _rows[index].controller.dispose();
      _rows.removeAt(index);
    });
    _emit();
  }

  void _setType(int index, String type) {
    if (_rows[index].type == type) return;
    setState(() => _rows[index].type = type);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ToggleButtons(
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
                  isSelected: [_rows[i].type == 'appel', _rows[i].type == 'whatsapp'],
                  onPressed: (idx) => _setType(i, idx == 0 ? 'appel' : 'whatsapp'),
                  children: const [
                    Icon(Icons.call_rounded, size: 18),
                    Icon(Icons.chat_rounded, size: 18),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _rows[i].controller,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => _emit(),
                    style: GoogleFonts.nunito(color: theme.textOnBackground),
                    decoration: InputDecoration(
                      hintText: 'Numéro (ex. +226 70 00 00 00)',
                      filled: true,
                      fillColor: theme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _remove(i),
                  icon: Icon(Icons.close_rounded, color: theme.textOnBackgroundMuted, size: 18),
                ),
              ],
            ),
          ),
        if (_rows.length < 3)
          TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter un contact'),
          ),
      ],
    );
  }
}

class _CeremoniesTab extends StatefulWidget {
  final dynamic theme;
  final Invitation invitation;
  final VoidCallback onChanged;

  const _CeremoniesTab({required this.theme, required this.invitation, required this.onChanged});

  @override
  State<_CeremoniesTab> createState() => _CeremoniesTabState();
}

class _CeremoniesTabState extends State<_CeremoniesTab> {
  Future<void> _openForm([InvitationCeremony? existing]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _CeremonyFormSheet(theme: widget.theme, existing: existing),
    );
    if (result == null) return;
    try {
      if (existing != null) {
        await InvitationService.instance.updateCeremony(widget.invitation.id, existing.id, result);
      } else {
        await InvitationService.instance.addCeremony(widget.invitation.id, result);
      }
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(InvitationCeremony ceremony) async {
    try {
      await InvitationService.instance.deleteCeremony(widget.invitation.id, ceremony.id);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final ceremonies = widget.invitation.ceremonies;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ceremonies.isEmpty
          ? Center(
              child: Text('Aucune cérémonie — ajoute la première avec le bouton +.', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: ceremonies.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final ceremony = ceremonies[index];
                return Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    onTap: () => _openForm(ceremony),
                    leading: ceremony.icon == null
                        ? null
                        : ceremony.icon!.contains('/')
                            ? SizedBox(width: 28, height: 28, child: Image.asset(_ceremonyIconAssetPath(ceremony.icon!)))
                            : Text(ceremony.icon!, style: const TextStyle(fontSize: 22)),
                    title: Text(ceremony.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
                    subtitle: Text(
                      [ceremony.date, ceremony.time, ceremony.address].where((e) => e != null && e.isNotEmpty).join(' · '),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: theme.textOnBackgroundMuted),
                      onPressed: () => _delete(ceremony),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: () => _openForm(), backgroundColor: theme.primary, child: const Icon(Icons.add_rounded)),
    );
  }
}

class _CeremonyFormSheet extends StatefulWidget {
  final dynamic theme;
  final InvitationCeremony? existing;

  const _CeremonyFormSheet({required this.theme, required this.existing});

  @override
  State<_CeremonyFormSheet> createState() => _CeremonyFormSheetState();
}

/// Bibliothèque d'icônes prédéfinies pour une cérémonie, groupées par
/// catégorie (voir demande utilisateur) — 109 images bundlées dans l'app
/// (assets/invitations/icons/{catégorie}/{nom}.webp), la clé stockée est
/// "catégorie/nom" (voir ceremonies.blade.php côté serveur, qui résout la
/// même clé vers son propre fichier stocké).
const Map<String, List<String>> _ceremonyIconCatalog = {
  'traditionnel': [
    'famille_assise', 'remise_dot', 'couple_traditionnel_1', 'echange_familles', 'calebasse',
    'noix_cola', 'poterie', 'benediction_tete',
    'couple_traditionnel_2', 'salutation_familles_2', 'danse_traditionnelle', 'couple_traditionnel_3', 'repas_traditionnel',
  ],
  'musulman': [
    'mains_priere_coran', 'signature_nikah', 'coran_lutrin', 'mains_priere_arche', 'mosquee',
    'imam', 'benediction_mains', 'poignee_main', 'tapis_priere', 'repas_traditionnel',
  ],
  'chretien': [
    'eglise', 'autel', 'pasteur_sermon', 'bible', 'alliances',
    'pasteur_couple', 'mains_priere', 'choeur', 'registre_signature', 'sortie_petales',
  ],
  'civil': [
    'mairie', 'famille_mairie', 'couple_arrivee', 'lecture_registre',
    'couple_mains', 'signature_registre', 'livret_mariage', 'sortie_confettis',
  ],
  'reception': [
    'cocktails', 'plateau_champagne', 'buffet', 'table_dressee', 'table_longue',
    'gateau_mariage', 'decoupe_gateau', 'toast', 'premiere_danse', 'danse_groupe',
    'dj', 'microphone', 'danseur_traditionnel', 'couple_instruments', 'guirlande_lumineuse',
  ],
  'photographie': [
    'photographe', 'photo_famille', 'selfie_groupe', 'photobooth',
    'videaste', 'livre_or', 'discours_micro', 'lancer_bouquet',
  ],
  'romantique': ['danse_couple', 'couple_arche', 'lettre_amour', 'allee_fleurs', 'valse_mariee', 'voiture_rubans'],
  'logistique': [
    'convoi_voitures', 'famille_accueil', 'bus_navette', 'voiture_lieu',
    'voiture_couple', 'chapelle_tente', 'chaises_decorees', 'voiture_depart',
  ],
  'preparatifs': [
    'henna_mains', 'maquillage', 'coiffure', 'robe_mariee',
    'costume_marie', 'tenue_traditionnelle', 'bagues_alliance', 'accessoires_mariee',
  ],
  'famille': ['salutation_familles', 'discours_officiant', 'benediction', 'bouquet_mariee', 'portrait_famille', 'poignee_main_familles'],
  'animations': ['petales_fleurs', 'ballons', 'cortege_famille', 'chanteur', 'djembe', 'feu_artifice', 'bougies'],
  'universelles': [
    'calendrier', 'horloge', 'localisation', 'coeur_alliance', 'etoiles',
    'bouquet', 'cloche', 'maison', 'famille_silhouette', 'champagne',
  ],
};

const Map<String, String> _ceremonyIconCategoryLabels = {
  'traditionnel': 'Traditionnel',
  'musulman': 'Musulman',
  'chretien': 'Chrétien',
  'civil': 'Civil',
  'reception': 'Réception',
  'photographie': 'Photographie',
  'romantique': 'Romantique',
  'logistique': 'Logistique',
  'preparatifs': 'Préparatifs',
  'famille': 'Famille',
  'animations': 'Animations',
  'universelles': 'Universelles',
};

String _ceremonyIconAssetPath(String key) => 'assets/invitations/icons/$key.webp';

/// Le backend stocke `time` en colonne TIME et le renvoie avec les secondes
/// (ex. "08:00:00") mais valide en écriture au format "H:i" uniquement
/// (voir InvitationCeremonyController::rules) — on tronque donc toujours
/// aux 5 premiers caractères "HH:mm" avant d'afficher ou d'envoyer.
String? _normalizeTime(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return '';
  return t.length >= 5 ? t.substring(0, 5) : t;
}

class _CeremonyFormSheetState extends State<_CeremonyFormSheet> {
  late final _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
  late final _timeCtrl = TextEditingController(text: _normalizeTime(widget.existing?.time));
  late final _addressCtrl = TextEditingController(text: widget.existing?.address ?? '');
  late final _instructionsCtrl = TextEditingController(text: widget.existing?.instructions ?? '');
  DateTime? _date;
  String? _selectedIcon;
  late String _iconCategory;

  @override
  void initState() {
    super.initState();
    final raw = widget.existing?.date;
    _date = raw != null ? DateTime.tryParse(raw) : null;
    _selectedIcon = widget.existing?.icon;
    _iconCategory = (_selectedIcon != null && _selectedIcon!.contains('/')) ? _selectedIcon!.split('/').first : 'universelles';
  }

  String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _submit() {
    if (_titleCtrl.text.trim().isEmpty) return;
    Navigator.of(context).pop({
      'title': _titleCtrl.text.trim(),
      'date': _date != null ? _isoDate(_date!) : null,
      'time': _normalizeTime(_timeCtrl.text.trim()),
      'address': _addressCtrl.text.trim(),
      'instructions': _instructionsCtrl.text.trim(),
      'icon': _selectedIcon,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing != null ? 'Modifier la cérémonie' : 'Nouvelle cérémonie', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, fontSize: 18, color: theme.textOnBackground)),
            const SizedBox(height: 16),
            _SectionField(label: 'Titre (ex. Mariage traditionnel)', controller: _titleCtrl, theme: theme),
            _DatePickerField(
              label: 'Date',
              value: _date,
              theme: theme,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 14),
            _SectionField(label: 'Heure (ex. 15:00)', controller: _timeCtrl, theme: theme),
            _SectionField(label: 'Adresse', controller: _addressCtrl, theme: theme, maxLines: 2),
            _SectionField(label: 'Instructions (optionnel)', controller: _instructionsCtrl, theme: theme, maxLines: 2),
            Text('Icône (optionnel)', style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
            const SizedBox(height: 8),
            _DropdownField<String>(
              theme: theme,
              label: 'Catégorie',
              value: _iconCategory,
              items: _ceremonyIconCategoryLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (cat) {
                if (cat != null) setState(() => _iconCategory = cat);
              },
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: (_ceremonyIconCatalog[_iconCategory] ?? const []).length,
              itemBuilder: (context, index) {
                final name = _ceremonyIconCatalog[_iconCategory]![index];
                final key = '$_iconCategory/$name';
                final isSelected = key == _selectedIcon;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedIcon = isSelected ? null : key),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? theme.primary : Colors.transparent, width: 2),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(_ceremonyIconAssetPath(key), fit: BoxFit.contain),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Enregistrer', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
