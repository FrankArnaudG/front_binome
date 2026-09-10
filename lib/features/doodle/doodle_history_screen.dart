import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/realtime_client.dart';
import '../../models/app_user.dart';
import '../../models/doodle.dart';
import '../box/box_scope.dart';
import '../games/pictionary/pictionary_canvas.dart';
import 'doodle_compose_screen.dart';
import 'doodle_service.dart';
import 'doodle_view_screen.dart';

/// Historique de TOUS les doodles échangés avec le binôme — UNE SEULE
/// discussion pour tous les envois (voir demande utilisateur), ouvrable à
/// tout moment depuis le Carnet de bord (voir TimelineScreen, qui
/// repositionne l'entrée correspondante selon le dernier doodle envoyé).
class DoodleHistoryScreen extends StatefulWidget {
  final AppUser user;

  const DoodleHistoryScreen({super.key, required this.user});

  @override
  State<DoodleHistoryScreen> createState() => _DoodleHistoryScreenState();
}

class _DoodleHistoryScreenState extends State<DoodleHistoryScreen> {
  List<Doodle>? _doodles;
  bool _loadError = false;
  String? _boxId;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final boxId = BoxScope.of(context).currentBox?.id;
    if (boxId != null && boxId != _boxId) {
      _boxId = boxId;
      RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
    }
  }

  @override
  void dispose() {
    if (_boxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_boxId!, onEvent: _onRealtimeEvent);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'DoodleSent') return;
    final data = event.data;
    if (data == null) return;
    final doodle = Doodle.fromJson(data['doodle'] as Map<String, dynamic>);
    if (!mounted || _doodles == null) return;
    // Ignore un doublon (ex. déjà ajouté par le fetch qui suit
    // l'ouverture, ou déjà reçu une fois — voir RealtimeClient, jamais la
    // seule source de vérité) plutôt que de l'afficher deux fois.
    if (_doodles!.any((d) => d.id == doodle.id)) return;
    setState(() => _doodles = [..._doodles!, doodle]);
    _scrollToBottom();
  }

  Future<void> _load() async {
    try {
      final doodles = await DoodleService.instance.fetchDoodles();
      if (!mounted) return;
      setState(() {
        _doodles = doodles;
        _loadError = false;
      });
      _scrollToBottom(animated: false);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _compose() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DoodleComposeScreen()),
    );
    _load();
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
    final partner = BoxScope.of(context).currentBox?.partnerOf(widget.user.id);

    return Scaffold(
      backgroundColor: const Color(0xFF14131C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          partner != null ? 'Mots & dessins avec ${partner.prenom}' : 'Mots & dessins',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_doodles == null && !_loadError) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_loadError && _doodles == null) {
              return Center(
                child: Text('Impossible de charger l\'historique.', style: GoogleFonts.nunito(color: Colors.white70)),
              );
            }
            final doodles = _doodles ?? const [];
            if (doodles.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Aucun mot échangé pour le moment.\nDessine le premier !',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(color: Colors.white70, fontSize: 14),
                  ),
                ),
              );
            }
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: doodles.length,
              itemBuilder: (context, index) {
                final doodle = doodles[index];
                final isMine = doodle.fromUserId == widget.user.id;
                return Align(
                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        // Agrandissable (voir demande utilisateur : "on doit
                        // pouvoir cliquer sur un pour l'agrandir et bien
                        // regarder") — ici avec un VRAI fond (voir demande
                        // utilisateur : "le fond doit exister"), contrairement
                        // à l'arrivée en direct qui reste transparente sur
                        // l'écran du dessous (voir DoodleOverlay).
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DoodleViewScreen(doodle: doodle, viewerUserId: widget.user.id, showBackground: true),
                            ),
                          ),
                          child: Container(
                            // Dimensions d'origine (voir demande utilisateur :
                            // "uniquement pour cet écran, remettre les
                            // dimensions d'avant") — une vignette d'historique
                            // n'a pas besoin de matcher exactement la forme
                            // de l'édition/réception, juste rester lisible et
                            // compacte dans la liste.
                            width: 200,
                            height: 160,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                            clipBehavior: Clip.antiAlias,
                            child: PictionaryCanvas(strokes: doodle.strokes, interactive: false),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_relativeTime(doodle.createdAt), style: GoogleFonts.nunito(fontSize: 11, color: Colors.white54)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        child: const Icon(Icons.brush_rounded),
      ),
    );
  }
}
