import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/empty_state.dart';
import 'invitation_editor_screen.dart';
import 'invitation_service.dart';
import 'models/invitation_models.dart';

/// Page d'accueil du module "Invitations numériques" (voir cahier des
/// charges) — catalogue de collections/modèles pour en démarrer une
/// nouvelle, et liste des invitations déjà créées par l'utilisateur pour y
/// revenir. Point d'entrée unique, ouvert depuis la tuile "Invitations" de
/// Duo/Action rapide (voir DarkQuickActionsGrid).
class InvitationCatalogueScreen extends StatefulWidget {
  const InvitationCatalogueScreen({super.key});

  @override
  State<InvitationCatalogueScreen> createState() => _InvitationCatalogueScreenState();
}

class _InvitationCatalogueScreenState extends State<InvitationCatalogueScreen> {
  bool _loading = true;
  Object? _error;
  List<InvitationTemplate> _templates = [];
  List<Invitation> _invitations = [];
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _load();
  }

  /// Affiche la dernière liste connue instantanément (voir
  /// InvitationService.cachedTemplates/cachedMyInvitations) pendant que [_load]
  /// refait la vraie requête en tâche de fond — évite un loader bloquant à
  /// chaque ouverture (voir demande utilisateur).
  Future<void> _loadFromCache() async {
    final results = await Future.wait([
      InvitationService.instance.cachedTemplates(),
      InvitationService.instance.cachedMyInvitations(),
    ]);
    final templates = results[0] as List<InvitationTemplate>?;
    final invitations = results[1] as List<Invitation>?;
    if (!mounted || (templates == null && invitations == null)) return;
    setState(() {
      _templates = templates ?? _templates;
      _invitations = invitations ?? _invitations;
      _loading = false;
    });
  }

  Future<void> _load() async {
    // Pas de loader bloquant si du contenu (même mis en cache) est déjà
    // affiché — seule la toute première ouverture sans aucun cache le montre.
    if (_templates.isEmpty && _invitations.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        InvitationService.instance.fetchTemplates(),
        InvitationService.instance.fetchMyInvitations(),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<InvitationTemplate>;
        _invitations = results[1] as List<Invitation>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Le cache reste affiché plutôt que de le remplacer par un écran
      // d'erreur — seule la toute première ouverture (rien en cache) montre
      // l'état d'erreur avec "Réessayer".
      setState(() {
        _loading = false;
        if (_templates.isEmpty && _invitations.isEmpty) _error = e;
      });
    }
  }

  Future<void> _startFromTemplate(InvitationTemplate template) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final invitation = await InvitationService.instance.createInvitation(template.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => InvitationEditorScreen(invitationId: invitation.id)),
      );
      if (mounted) _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openInvitation(Invitation invitation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InvitationEditorScreen(invitationId: invitation.id)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        title: Text(
          'Invitations',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        iconTheme: IconThemeData(color: theme.textOnBackground),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  message: _error is ApiException ? (_error as ApiException).message : 'Impossible de charger. Réessaie dans un instant.',
                  actionLabel: 'Réessayer',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Text(
                        'Nouvelle invitation',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: theme.textOnBackground),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choisis une collection pour commencer.',
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 184,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _templates.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) => _TemplateCard(
                            template: _templates[index],
                            theme: theme,
                            loading: _creating,
                            onTap: () => _startFromTemplate(_templates[index]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Mes invitations',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: theme.textOnBackground),
                      ),
                      const SizedBox(height: 14),
                      if (_invitations.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            "Aucune invitation pour l'instant — commence avec un modèle ci-dessus.",
                            style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                          ),
                        )
                      else
                        ..._invitations.map((inv) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _InvitationTile(invitation: inv, theme: theme, onTap: () => _openInvitation(inv)),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final InvitationTemplate template;
  final dynamic theme;
  final bool loading;
  final VoidCallback onTap;

  const _TemplateCard({required this.template, required this.theme, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Hauteurs FIXES plutôt qu'un AspectRatio combiné à la hauteur fixe du
    // SizedBox parent (voir InvitationCatalogueScreen._build) — les deux
    // ensemble dépassaient la hauteur disponible et débordaient (voir
    // demande utilisateur : "problème de pixel").
    return SizedBox(
      width: 140,
      child: Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: loading ? null : onTap,
          child: Opacity(
            opacity: loading ? 0.6 : 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: template.previewImageUrl != null
                        ? CachedNetworkImage(imageUrl: template.previewImageUrl!, fit: BoxFit.cover)
                        : Container(
                            color: theme.primary.withValues(alpha: 0.12),
                            child: Icon(Icons.favorite_rounded, color: theme.primary, size: 32),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        template.collectionKey.replaceAll('_', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted),
                      ),
                    ],
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

class _InvitationTile extends StatelessWidget {
  final Invitation invitation;
  final dynamic theme;
  final VoidCallback onTap;

  const _InvitationTile({required this.invitation, required this.theme, required this.onTap});

  // Couleurs du thème de l'APP (voir ThemePalette), pas celles de
  // l'invitation elle-même (#681D32 etc.) — ce badge est un élément de
  // l'interface de Binôme, pas de la page publiée (voir demande
  // utilisateur : "ne respecte pas la charte graphique de l'app").
  (String, Color) _statusBadge() {
    switch (invitation.status) {
      case 'published':
        return ('En ligne', theme.accent);
      case 'suspended':
        return ('Suspendue', theme.secondary);
      case 'archived':
        return ('Archivée', theme.textOnBackgroundMuted);
      default:
        return ('Brouillon', theme.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = [invitation.partnerOneName, invitation.partnerTwoName].where((n) => n != null && n.isNotEmpty).join(' & ');
    final (statusLabel, statusColor) = _statusBadge();
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.mail_rounded, color: statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names.isEmpty ? 'Sans nom pour le moment' : names,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                          child: Text(statusLabel, style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                        ),
                        if (invitation.eventCity != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              invitation.eventCity!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Utilitaire partagé par l'éditeur/catalogue pour ouvrir un lien externe
/// (prévisualisation ou invitation publiée) — toujours dans le navigateur
/// du téléphone, jamais une WebView interne (voir cahier des charges §8).
Future<void> openExternalLink(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
