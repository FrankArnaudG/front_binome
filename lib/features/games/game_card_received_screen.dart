import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/send.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../content/content_service.dart';
import 'game_card_inbox_service.dart';
import 'game_service.dart';

/// Carte-question reçue (voir la bulle de notification dans AppShell) : la
/// personne qui la reçoit peut y répondre, la "retourner" (renvoyer la même
/// question à qui l'a envoyée) ou piocher une nouvelle carte à envoyer à la
/// place.
class GameCardReceivedScreen extends StatefulWidget {
  final Send send;

  const GameCardReceivedScreen({super.key, required this.send});

  @override
  State<GameCardReceivedScreen> createState() => _GameCardReceivedScreenState();
}

class _GameCardReceivedScreenState extends State<GameCardReceivedScreen> {
  final _answerController = TextEditingController();
  bool _submitting = false;
  bool _answering = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer() async {
    final text = _answerController.text.trim();
    if (text.isEmpty || _submitting) return;
    await _sendAnswer(text);
  }

  /// Un Défi n'a pas de réponse écrite — juste une confirmation, voir
  /// widget.send.gameCard.isDefi.
  Future<void> _confirmDefi() => _sendAnswer('Défi relevé ✅');

  Future<void> _sendAnswer(String text) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await GameService.instance.answerCard(widget.send.gameCard!.id, text);
      GameCardInboxService.instance.removePending(widget.send.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _bounce() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await GameService.instance.bounceCard(widget.send.gameCard!.id);
      GameCardInboxService.instance.removePending(widget.send.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Question relancée 🔁')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _drawAndSendInstead() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final gameCard = widget.send.gameCard!;
    try {
      await ContentService.instance.markSeen(widget.send.id);
      final boxes = await GameService.instance.fetchBoxes(gameCard.gameId);
      final matches = boxes.where((b) => b.id == gameCard.gameBoxId);
      final box = matches.isEmpty ? null : matches.first;
      // Pour Vérité ou Défi, on repioche dans la même catégorie — renvoyer
      // un Défi ne doit pas accidentellement tirer une Vérité.
      final pool = gameCard.category == null
          ? box?.questions.toList()
          : box?.questions.where((q) => q.category == gameCard.category).toList();
      if (box == null || pool == null || pool.isEmpty) {
        throw ApiException("Impossible de piocher une nouvelle carte pour l'instant.", 422);
      }
      final question = (pool..shuffle()).first;
      await GameService.instance.sendCard(gameCard.gameId, box.id, question.id);
      GameCardInboxService.instance.removePending(widget.send.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nouvelle carte envoyée 💌')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final gameCard = widget.send.gameCard!;
    final senderName = widget.send.sender?.prenom ?? 'Ton/ta partenaire';
    final isDefi = gameCard.isDefi;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          gameCard.gameBoxTitleFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isDefi ? '$senderName te lance un défi 🔥' : '$senderName t\'a envoyé une carte 💌',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.primary.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(color: theme.primary.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Text(
                    gameCard.questionTextFor(localeCode),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4, color: theme.textOnBackground),
                  ),
                ),
                const SizedBox(height: 24),
                if (isDefi) ...[
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _submitting ? null : _confirmDefi,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _submitting
                                ? const Center(
                                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                                  )
                                : const Text(
                                    'Défi relevé ✅',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _bounce,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Je te le relance, à $senderName de le relever aussi 🔁',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _submitting ? null : _drawAndSendInstead,
                      child: Text(
                        'Piocher un autre défi et l\'envoyer',
                        style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ] else if (_answering) ...[
                  TextField(
                    controller: _answerController,
                    autofocus: true,
                    maxLines: 3,
                    style: GoogleFonts.nunito(color: theme.textOnBackground),
                    cursorColor: theme.primary,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.surface,
                      hintText: 'Écris ta réponse…',
                      hintStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _submitting ? null : _submitAnswer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _submitting
                                ? const Center(
                                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                                  )
                                : Text(
                                    'Envoyer ma réponse',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _answering = true),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Répondre',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _bounce,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Retourner la question à $senderName',
                        style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _submitting ? null : _drawAndSendInstead,
                      child: Text(
                        'Piocher une autre carte et l\'envoyer',
                        style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
