import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'event_page.dart';
import 'event_page_rsvp.dart';
import 'event_page_service.dart';

/// Réponses RSVP laissées par les invités — voir demande utilisateur : "les
/// reponse doive etre visible dans lapp".
class EventPageRsvpListScreen extends StatefulWidget {
  final EventPage page;
  const EventPageRsvpListScreen({super.key, required this.page});

  @override
  State<EventPageRsvpListScreen> createState() => _EventPageRsvpListScreenState();
}

class _EventPageRsvpListScreenState extends State<EventPageRsvpListScreen> {
  List<EventPageRsvp>? _rsvps;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rsvps = await EventPageService.instance.listRsvps(widget.page.id);
      if (mounted) setState(() => _rsvps = rsvps);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final yesCount = _rsvps?.where((r) => r.attending == true).length ?? 0;
    final noCount = _rsvps?.where((r) => r.attending == false).length ?? 0;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text('Réponses RSVP', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _rsvps == null
              ? (_loadError
                  ? Center(child: Text('Impossible de charger les réponses.', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)))
                  : const Center(child: CircularProgressIndicator()))
              : _rsvps!.isEmpty
                  ? const EmptyState(
                      icon: Icons.how_to_reg_outlined,
                      message: 'Aucune réponse pour l\'instant.',
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(child: _StatChip(label: 'Présents', count: yesCount, color: Colors.green)),
                              const SizedBox(width: 10),
                              Expanded(child: _StatChip(label: 'Absents', count: noCount, color: Colors.redAccent)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _rsvps!.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final r = _rsvps![i];
                              return Material(
                                color: theme.surface,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        r.attending == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                        color: r.attending == true ? Colors.green : Colors.redAccent,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.guestName,
                                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
                                            if (r.message?.isNotEmpty == true) ...[
                                              const SizedBox(height: 4),
                                              Text(r.message!, style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text('$count', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: color)),
          Text(label, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
        ],
      ),
    );
  }
}
