import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/empty_state.dart';
import 'event_page.dart';
import 'event_page_designs.dart';
import 'event_page_editor_screen.dart';
import 'event_page_service.dart';

/// Liste des pages événement du user (+ celles que son binome a partagées
/// avec lui, voir EventPage::isAccessibleBy côté backend) — voir demande
/// utilisateur : "on peu avoir au maximun 10 evenement paramettrer".
class EventPagesListScreen extends StatefulWidget {
  const EventPagesListScreen({super.key});

  @override
  State<EventPagesListScreen> createState() => _EventPagesListScreenState();
}

class _EventPagesListScreenState extends State<EventPagesListScreen> {
  static const maxPages = 10;

  List<EventPage>? _pages;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pages = await EventPageService.instance.list();
      if (mounted) setState(() => _pages = pages);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  Future<void> _create() async {
    final pages = _pages ?? [];
    if (pages.length >= maxPages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limite de 10 pages événement atteinte, supprimez-en une pour continuer.')),
      );
      return;
    }

    // Voir demande utilisateur : "un formulaire simple pour demander les
    // info necessaire... dans ca on aura les theme a choisir aussi" — le
    // design se choisit DANS le formulaire, rien n'est créé côté serveur
    // avant le premier enregistrement (voir EventPageEditorScreen._save).
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventPageEditorScreen(page: null)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          'Pages événement',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 16), child: Center(child: CoinBalanceBadge())),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: theme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Créer'),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _pages == null
              ? (_loadError
                  ? Center(
                      child: Text('Impossible de charger tes pages événement.',
                          style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)))
                  : const Center(child: CircularProgressIndicator()))
              : _pages!.isEmpty
                  ? const EmptyState(
                      icon: Icons.favorite_border_rounded,
                      message: 'Aucune page événement pour l\'instant.\nCrée une page mariage à partager avec tes proches.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: _pages!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _EventPageCard(
                        page: _pages![i],
                        onTap: () async {
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => EventPageEditorScreen(page: _pages![i])));
                          _load();
                        },
                      ),
                    ),
        ),
      ),
    );
  }
}

class _EventPageCard extends StatefulWidget {
  final EventPage page;
  final VoidCallback onTap;

  const _EventPageCard({required this.page, required this.onTap});

  @override
  State<_EventPageCard> createState() => _EventPageCardState();
}

class _EventPageCardState extends State<_EventPageCard> {
  bool _previewing = false;

  /// Voir demande utilisateur : "ajouter une icon pour previsualier ici" —
  /// raccourci directement depuis la liste, sans passer par l'éditeur.
  Future<void> _preview() async {
    setState(() => _previewing = true);
    try {
      final url = await EventPageService.instance.fetchPreviewUrl(widget.page.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final page = widget.page;
    final design = kEventPageDesigns.firstWhere(
      (d) => d.key == page.design,
      orElse: () => kEventPageDesigns.first,
    );

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: design.color, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.favorite_rounded, color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.coupleNames?.isNotEmpty == true ? page.coupleNames! : 'Sans titre',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(design.label, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                  ],
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: _previewing
                    ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.visibility_outlined, size: 20, color: theme.textOnBackgroundMuted),
                        tooltip: 'Prévisualiser',
                        onPressed: _preview,
                      ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: page.isPublished ? Colors.green.withValues(alpha: .15) : theme.accent.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  page.isPublished ? 'Publié' : 'Brouillon',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: page.isPublished ? Colors.green : theme.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
