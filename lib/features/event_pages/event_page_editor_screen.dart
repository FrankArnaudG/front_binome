import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'event_page.dart';
import 'event_page_designs.dart';
import 'event_page_publish_flow.dart';
import 'event_page_rsvp_list_screen.dart';
import 'event_page_service.dart';

/// Formulaire d'édition d'une page événement — pas de wizard existant à
/// réutiliser dans l'app, formulaire simple à défilement unique (même
/// esprit que ProfileCompletionScreen). Toutes les sections sont
/// individuellement activables/désactivables (voir demande utilisateur).
///
/// [page] null = nouvelle page : voir demande utilisateur, "un formulaire
/// simple pour demander les info necessaire... dans ca on aura les theme a
/// choisir aussi" — aucun appel réseau au choix du design, la page n'est
/// créée côté serveur qu'au premier "Enregistrer le brouillon" (voir
/// _save), avec tout le contenu déjà saisi en un seul envoi.
class EventPageEditorScreen extends StatefulWidget {
  final EventPage? page;

  const EventPageEditorScreen({super.key, required this.page});

  @override
  State<EventPageEditorScreen> createState() => _EventPageEditorScreenState();
}

class _EventPageEditorScreenState extends State<EventPageEditorScreen> {
  EventPage? _page;
  late String _design;
  late bool _shared;
  late Map<String, bool> _sections;
  late List<Map<String, dynamic>> _programme;

  final _coupleNamesCtrl = TextEditingController();
  final _venueNameCtrl = TextEditingController();
  final _venueCityCtrl = TextEditingController();
  final _venueAddressCtrl = TextEditingController();
  final _histoireCtrl = TextEditingController();
  final _dressCodeCtrl = TextEditingController();
  final _merciCtrl = TextEditingController();
  DateTime? _eventDate;

  bool _saving = false;
  bool _previewing = false;
  bool _uploadingImage = false;
  // Point de focus de l'image de couverture (voir demande utilisateur :
  // "l'image est coupée" → point de focus ajustable) — état local pour un
  // retour visuel immédiat pendant le glisser, synchronisé avec _page à
  // chaque remplacement (initState, après upload/suppression d'image).
  double _coverFocusX = 50;
  double _coverFocusY = 50;

  /// Vrai tant que le contenu affiché est l'exemple du thème (voir demande
  /// utilisateur : "pour chaque theme creer des example") et non du
  /// contenu saisi par l'utilisateur — passe à faux dès la première
  /// frappe, pour ne plus jamais écraser ce qu'il a tapé en changeant de
  /// design ensuite.
  bool _usingExample = false;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
    _design = _page?.design ?? kEventPageDesigns.first.key;
    _shared = _page?.sharedWithPartner ?? false;
    _sections = {for (final s in kEventPageSections) s.key: _page?.sectionsVisibility[s.key] ?? true};
    _programme = List<Map<String, dynamic>>.from((_page?.programme ?? const []).map((e) => Map<String, dynamic>.from(e)));
    _coupleNamesCtrl.text = _page?.coupleNames ?? '';
    _venueNameCtrl.text = _page?.venueName ?? '';
    _venueCityCtrl.text = _page?.venueCity ?? '';
    _venueAddressCtrl.text = _page?.venueAddress ?? '';
    _histoireCtrl.text = _page?.notreHistoire ?? '';
    _dressCodeCtrl.text = _page?.dressCodeText ?? '';
    _merciCtrl.text = _page?.merciMessage ?? '';
    _eventDate = _page?.eventDate;
    _coverFocusX = _page?.coverImageFocusX ?? 50;
    _coverFocusY = _page?.coverImageFocusY ?? 50;

    if (_page == null) {
      _usingExample = true;
      _applyExample(_design);
    }
  }

  void _applyExample(String designKey) {
    final example = kEventPageExamples[designKey];
    if (example == null) return;
    _coupleNamesCtrl.text = example.coupleNames;
    _venueNameCtrl.text = example.venueName;
    _venueCityCtrl.text = example.venueCity;
    _venueAddressCtrl.text = example.venueAddress;
    _histoireCtrl.text = example.notreHistoire;
    _dressCodeCtrl.text = example.dressCodeText;
    _merciCtrl.text = example.merciMessage;
    _programme = example.programme.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _onUserEdited() {
    if (_usingExample) setState(() => _usingExample = false);
  }

  @override
  void dispose() {
    _coupleNamesCtrl.dispose();
    _venueNameCtrl.dispose();
    _venueCityCtrl.dispose();
    _venueAddressCtrl.dispose();
    _histoireCtrl.dispose();
    _dressCodeCtrl.dispose();
    _merciCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _fields() => {
        'design': _design,
        'shared_with_partner': _shared,
        'couple_names': _coupleNamesCtrl.text.trim(),
        'event_date': _eventDate?.toIso8601String().split('T').first,
        'venue_name': _venueNameCtrl.text.trim(),
        'venue_city': _venueCityCtrl.text.trim(),
        'venue_address': _venueAddressCtrl.text.trim(),
        'notre_histoire': _histoireCtrl.text.trim(),
        'dress_code_text': _dressCodeCtrl.text.trim(),
        'merci_message': _merciCtrl.text.trim(),
        'programme': _programme,
        'sections_visibility': _sections,
        'cover_image_focus_x': _coverFocusX,
        'cover_image_focus_y': _coverFocusY,
      };

  /// Crée la page au premier enregistrement, met à jour ensuite — un seul
  /// formulaire pour les deux cas (voir demande utilisateur).
  Future<bool> _save({bool silent = false}) async {
    setState(() => _saving = true);
    try {
      final page = _page;
      final saved = page == null
          ? await EventPageService.instance.create(_fields())
          : await EventPageService.instance.update(page.id, _fields());
      if (!mounted) return false;
      setState(() => _page = saved);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brouillon enregistré.')));
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message = e is ApiException ? e.message : 'Une erreur est survenue.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final page = _page;
    if (page == null) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette page ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    await EventPageService.instance.destroy(page.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _publish() async {
    if (!await _save(silent: true)) return;
    if (!mounted) return;
    final published = await runEventPagePublishFlow(context, _page!);
    if (published != null && mounted) setState(() => _page = published);
  }

  /// Voir demande utilisateur : "apres ca on peu previsualier" — enregistre
  /// d'abord (silencieusement) si nécessaire pour que l'aperçu reflète le
  /// contenu courant, puis ouvre le lien signé dans le navigateur.
  Future<void> _preview() async {
    setState(() => _previewing = true);
    try {
      if (!await _save(silent: true)) return;
      if (!mounted) return;
      final url = await EventPageService.instance.fetchPreviewUrl(_page!.id);
      if (!mounted) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Impossible d\'ouvrir l\'aperçu.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  /// Image de couverture optionnelle — voir demande utilisateur : "des
  /// gens trouvent ça assez basique, veulent ajouter une image" ; la
  /// compression (50 Ko max) se fait côté serveur (voir
  /// EventPageController::compressCoverImage), jamais ici. L'upload a
  /// besoin d'un id de page existant — un brouillon est créé
  /// silencieusement d'abord si on n'en a pas encore (même principe que
  /// _publish/_preview).
  Future<void> _pickAndUploadCoverImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      if (_page == null && !await _save(silent: true)) return;
      if (!mounted) return;
      final updated = await EventPageService.instance.uploadCoverImage(_page!.id, File(picked.path));
      if (!mounted) return;
      setState(() {
        _page = updated;
        _coverFocusX = updated.coverImageFocusX;
        _coverFocusY = updated.coverImageFocusY;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Impossible d\'ajouter cette image.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _removeCoverImage() async {
    final page = _page;
    if (page == null) return;
    setState(() => _uploadingImage = true);
    try {
      final updated = await EventPageService.instance.deleteCoverImage(page.id);
      if (!mounted) return;
      setState(() => _page = updated);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Impossible de retirer cette image.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _addProgrammeItem() {
    setState(() {
      _programme.add({'time': '', 'title': '', 'subtitle': ''});
      _usingExample = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final page = _page;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          page == null ? 'Nouvelle page événement' : 'Page événement',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (page?.isPublished == true) _PublishedBanner(page: page!),
              if (_usingExample) _ExampleBanner(theme: theme),
              const SizedBox(height: 12),
              _sectionTitle(theme, 'Design'),
              _designPicker(theme),
              const SizedBox(height: 20),
              _sectionTitle(theme, 'Photo de couverture'),
              _coverImagePicker(theme),
              if (_page?.coverImageUrl != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Glisse sur la photo pour choisir la partie qui reste visible.',
                  style: GoogleFonts.nunito(fontSize: 11.5, color: theme.textOnBackgroundMuted),
                ),
              ],
              const SizedBox(height: 20),
              _sectionTitle(theme, 'Contenu'),
              _field(theme, _coupleNamesCtrl, 'Noms du couple', hint: 'Aïcha & Karim'),
              const SizedBox(height: 10),
              _datePicker(theme),
              const SizedBox(height: 10),
              _field(theme, _venueNameCtrl, 'Nom du lieu'),
              const SizedBox(height: 10),
              _field(theme, _venueAddressCtrl, 'Adresse'),
              const SizedBox(height: 10),
              _field(theme, _venueCityCtrl, 'Ville'),
              const SizedBox(height: 10),
              _field(theme, _histoireCtrl, 'Notre histoire', maxLines: 4),
              const SizedBox(height: 10),
              _field(theme, _dressCodeCtrl, 'Dress code', maxLines: 2),
              const SizedBox(height: 10),
              _field(theme, _merciCtrl, 'Message de remerciement', maxLines: 3),
              const SizedBox(height: 20),
              _sectionTitle(theme, 'Programme'),
              ..._programme.asMap().entries.map((entry) => _programmeRow(theme, entry.key)),
              TextButton.icon(
                onPressed: _addProgrammeItem,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter une étape'),
              ),
              const SizedBox(height: 20),
              _sectionTitle(theme, 'Sections visibles'),
              for (final s in kEventPageSections)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.label, style: GoogleFonts.nunito(color: theme.textOnBackground)),
                  value: _sections[s.key] ?? true,
                  activeColor: theme.primary,
                  onChanged: (v) => setState(() => _sections[s.key] = v),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Partager avec mon binome', style: GoogleFonts.nunito(color: theme.textOnBackground)),
                subtitle: Text('Il/elle pourra voir et modifier cette page.',
                    style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                value: _shared,
                activeColor: theme.primary,
                onChanged: (v) => setState(() => _shared = v),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _previewing ? null : _preview,
                icon: _previewing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.visibility_outlined),
                label: const Text('Prévisualiser'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _saving ? null : () => _save(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.surface,
                  foregroundColor: theme.textOnBackground,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enregistrer le brouillon'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _saving ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(page?.isPublished == true ? 'Mettre à jour la page publique' : 'Publier'),
              ),
              if (page?.isPublished == true) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventPageRsvpListScreen(page: page!))),
                  icon: const Icon(Icons.how_to_reg_rounded),
                  label: const Text('Voir les réponses RSVP'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(dynamic theme, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground)),
      );

  Widget _field(dynamic theme, TextEditingController ctrl, String label, {String? hint, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: (_) => _onUserEdited(),
      style: GoogleFonts.nunito(color: theme.textOnBackground),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: theme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _datePicker(dynamic theme) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _eventDate ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
        );
        if (picked != null) setState(() => _eventDate = picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date de l\'événement',
          filled: true,
          fillColor: theme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
        child: Text(
          _eventDate != null ? '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}' : 'Choisir une date',
          style: GoogleFonts.nunito(color: theme.textOnBackground),
        ),
      ),
    );
  }

  Widget _designPicker(dynamic theme) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kEventPageDesigns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final d = kEventPageDesigns[i];
          final selected = d.key == _design;
          return InkWell(
            onTap: () => setState(() {
              _design = d.key;
              if (_usingExample) _applyExample(d.key);
            }),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 130,
              decoration: BoxDecoration(
                color: d.color,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(color: theme.primary, width: 3)
                    : (d.borderColor != null ? Border.all(color: d.borderColor!) : null),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                d.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: d.textColor),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Voir demande utilisateur : "l'image est coupée" → point de focus
  /// ajustable plutôt qu'un cadre adapté au ratio de la photo. [localPos]
  /// est relatif au widget du GestureDetector (voir _coverImagePicker).
  void _updateCoverFocusFrom(Offset localPos, Size size) {
    if (size.width == 0 || size.height == 0) return;
    setState(() {
      _coverFocusX = (localPos.dx / size.width * 100).clamp(0, 100);
      _coverFocusY = (localPos.dy / size.height * 100).clamp(0, 100);
    });
  }

  Widget _coverImagePicker(dynamic theme) {
    final url = _page?.coverImageUrl;
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: url != null
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        onPanUpdate: (details) => _updateCoverFocusFrom(details.localPosition, size),
                        onPanEnd: (_) => _save(silent: true),
                        onTapUp: (details) {
                          _updateCoverFocusFrom(details.localPosition, size);
                          _save(silent: true);
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              alignment: Alignment((_coverFocusX / 100) * 2 - 1, (_coverFocusY / 100) * 2 - 1),
                            ),
                            Positioned(
                              left: _coverFocusX / 100 * size.width - 12,
                              top: _coverFocusY / 100 * size.height - 12,
                              child: IgnorePointer(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : InkWell(
                    onTap: _uploadingImage ? null : _pickAndUploadCoverImage,
                    child: Container(
                      color: theme.surface,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, color: theme.textOnBackgroundMuted, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            'Ajouter une image',
                            style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackgroundMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        if (_uploadingImage) const CircularProgressIndicator(),
        if (url != null && !_uploadingImage)
          Positioned(
            right: 8,
            top: 8,
            child: Row(
              children: [
                _coverImageActionButton(Icons.edit_rounded, _pickAndUploadCoverImage),
                const SizedBox(width: 6),
                _coverImageActionButton(Icons.close_rounded, _removeCoverImage),
              ],
            ),
          ),
      ],
    );
  }

  Widget _coverImageActionButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  Widget _programmeRow(dynamic theme, int index) {
    final item = _programme[index];
    return Padding(
      // Clé liée au design : force la recréation des champs quand
      // l'exemple change de thème, sinon Flutter réutilise l'ancien state
      // du TextFormField et ignore le nouvel `initialValue` (voir demande
      // utilisateur : "pour chaque theme creer des example").
      key: ValueKey('programme-$_design-$index'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: TextFormField(
              initialValue: item['time'] as String? ?? '',
              onChanged: (v) {
                item['time'] = v;
                _onUserEdited();
              },
              decoration: InputDecoration(
                hintText: '10h00',
                filled: true,
                fillColor: theme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: item['title'] as String? ?? '',
              onChanged: (v) {
                item['title'] = v;
                _onUserEdited();
              },
              decoration: InputDecoration(
                hintText: 'Cérémonie',
                filled: true,
                fillColor: theme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _programme.removeAt(index);
              _onUserEdited();
            }),
          ),
        ],
      ),
    );
  }
}

class _ExampleBanner extends StatelessWidget {
  final dynamic theme;
  const _ExampleBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: theme.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: theme.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Contenu d\'exemple pour ce thème — remplace-le par tes informations.',
                style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedBanner extends StatelessWidget {
  final EventPage page;
  const _PublishedBanner({required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.green.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.public_rounded, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(page.publicUrl, style: GoogleFonts.nunito(color: theme.textOnBackground), overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: page.publicUrl));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié.')));
            },
          ),
        ],
      ),
    );
  }
}
