import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../support_service.dart';

/// "Nous contacter" (voir AboutCard) — formulaire minimal (sujet + message)
/// plutôt qu'une vraie messagerie : la réponse se fait par email, en dehors
/// de l'app (voir SupportTicketController côté backend).
Future<void> showContactDialog(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _ContactDialog());
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      _subjectController.text.trim().isNotEmpty &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await SupportService.instance.submitTicket(
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
      );
      if (!mounted) return;
      final t = LocaleScope.of(context).t;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('contact_sent_snackbar'))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = LocaleScope.of(context).t('contact_generic_error'),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        t('contact_title'),
        style: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: theme.textOnBackground,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('contact_subtitle'),
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: theme.textOnBackgroundMuted,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subjectController,
              maxLength: 120,
              style: TextStyle(color: theme.textOnBackground),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t('contact_subject_label'),
                labelStyle: TextStyle(color: theme.textOnBackgroundMuted),
              ),
            ),
            TextField(
              controller: _messageController,
              maxLines: 4,
              maxLength: 2000,
              style: TextStyle(color: theme.textOnBackground),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t('contact_message_label'),
                labelStyle: TextStyle(color: theme.textOnBackgroundMuted),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(t('common_cancel')),
        ),
        TextButton(
          onPressed: _canSend ? _send : null,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('contact_send')),
        ),
      ],
    );
  }
}
