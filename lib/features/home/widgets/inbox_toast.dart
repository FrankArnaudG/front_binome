import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/send.dart';
import '../../games/pending_send_helpers.dart';

/// Bannière temporaire (voir aussi GameCardBubble, la notification
/// persistante) — s'ouvre pendant quelques secondes en haut de l'écran
/// quand un nouvel envoi (carte-question, story en émojis, poème-slide ou
/// battement de cœur) arrive pendant que l'app est déjà ouverte, avec un
/// aperçu de qui a envoyé quoi. Un tap dessus ouvre directement la
/// discussion concernée (voir openPendingSend, même logique de navigation
/// que la bulle) au lieu de simplement la refermer.
class InboxToast {
  static void show(BuildContext context, Send send) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _InboxToastBanner(send: send, onDismiss: () => entry.remove()),
    );

    overlay.insert(entry);
  }
}

class _InboxToastBanner extends StatefulWidget {
  final Send send;
  final VoidCallback onDismiss;

  const _InboxToastBanner({required this.send, required this.onDismiss});

  @override
  State<_InboxToastBanner> createState() => _InboxToastBannerState();
}

class _InboxToastBannerState extends State<_InboxToastBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
  );

  bool _dismissed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(seconds: 5), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _controller.reverse();
    widget.onDismiss();
  }

  Future<void> _open() async {
    if (_opening || _dismissed) return;
    setState(() => _opening = true);
    await openPendingSend(widget.send);
    await _dismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final send = widget.send;
    final senderName = send.sender?.prenom ?? send.sender?.name ?? 'Ton binôme';
    final preview = previewForPendingSend(send, LocaleScope.of(context).current.code);
    final hasAvatar = send.sender?.avatar != null && send.sender!.avatar!.isNotEmpty;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _open,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [Color(0xFFFF3B5C), Color(0xFF7B2D8E)]),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: hasAvatar ? NetworkImage(send.sender!.avatar!) : null,
                    child: hasAvatar ? null : Icon(iconForPendingSend(send), color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$senderName t\'a envoyé quelque chose',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_opening)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else
                    const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
