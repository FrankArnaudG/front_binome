import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/mood.dart';
import '../../theme/theme_scope.dart';
import 'mood_service.dart';

/// "Notre Humeur du Jour" — écran dédié (voir demande utilisateur : plutôt
/// qu'afficher les choix directement sur le Dashboard, un écran à part
/// accessible depuis les Actions rapides). Chaque option est une petite
/// illustration fournie par l'utilisateur (voir assets/humeur, assets/besoin,
/// assets/envi) — le libellé est déjà intégré à l'image, pas de texte
/// superposé. Reprend l'humeur déjà postée aujourd'hui si elle existe, pour
/// rester modifiable dans la journée (voir MoodService.share, qui écrase
/// l'entrée du jour).
class MoodScreen extends StatefulWidget {
  final AppUser user;
  final String? partnerName;
  final String? partnerGender;

  const MoodScreen({super.key, required this.user, this.partnerName, this.partnerGender});

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _moodKey;
  String? _needKey;
  String? _desireKey;
  Mood? _partnerMood;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (mine, partner, _, _) = await MoodService.instance.fetchToday();
      if (!mounted) return;
      setState(() {
        _moodKey = mine?.moodKey;
        _needKey = mine?.needKey;
        _desireKey = mine?.desireKey;
        _partnerMood = partner;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_moodKey == null || _saving) return;
    setState(() => _saving = true);
    try {
      await MoodService.instance.share(moodKey: _moodKey!, needKey: _needKey, desireKey: _desireKey);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : LocaleScope.of(context).t('mood_error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        foregroundColor: theme.textOnBackground,
        title: Text(t('mood_card_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // Explique le mécanisme (voir demande utilisateur) : sans
                  // ce texte, rien n'indiquait qu'il fallait aussi que le
                  // binôme renseigne SA propre humeur/besoin/envie pour
                  // obtenir la météo du couple, ni qu'il fallait revenir
                  // voir une fois les deux renseignés.
                  Text(
                    t('mood_screen_intro'),
                    style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackgroundMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Text(t('mood_card_prompt'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted)),
                  const SizedBox(height: 14),
                  _CardChoiceRow(
                    keys: kMoodKeys,
                    selectedKey: _moodKey,
                    theme: theme,
                    imageFor: (key) => moodAssetPath(key, widget.user.gender),
                    onTap: (key) => setState(() => _moodKey = key),
                  ),
                  const SizedBox(height: 24),
                  Text(t('mood_need_label'), style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted)),
                  const SizedBox(height: 10),
                  _CardChoiceRow(
                    keys: kNeedKeys,
                    selectedKey: _needKey,
                    theme: theme,
                    imageFor: (key) => needAssetPath(key, widget.user.gender),
                    onTap: (key) => setState(() => _needKey = key),
                  ),
                  const SizedBox(height: 24),
                  Text(t('mood_desire_label'), style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted)),
                  const SizedBox(height: 10),
                  _CardChoiceRow(
                    keys: kDesireKeys,
                    selectedKey: _desireKey,
                    theme: theme,
                    imageFor: (key) => desireAssetPath(key),
                    onTap: (key) => setState(() => _desireKey = key),
                  ),
                  if (_partnerMood != null) ...[
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 52,
                              height: 52,
                              color: theme.surface,
                              child: Image.asset(
                                moodAssetPath(_partnerMood!.moodKey, widget.partnerGender),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.partnerName != null
                                  ? t('mood_partner_today', {'name': widget.partnerName!})
                                  : t('mood_partner_today_fallback'),
                              style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      // Humeur, besoin et envie sont désormais tous les
                      // trois obligatoires (voir demande utilisateur) — les
                      // 4096 combinaisons du fichier de suggestions
                      // supposent que les trois sont toujours renseignés.
                      onPressed: _moodKey == null || _needKey == null || _desireKey == null || _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(t('mood_save_cta'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Rangée horizontale défilable de cartes montrant l'image complète (texte
/// intégré compris), sans découpe — voir demande utilisateur : défilement
/// horizontal, puis retour au format carte après comparaison avec des
/// variantes en cercle qui coupaient le texte des images. Pas de libellé
/// séparé : le texte de l'image fait déjà le travail.
class _CardChoiceRow extends StatefulWidget {
  final List<String> keys;
  final String? selectedKey;
  final dynamic theme;
  final String Function(String key) imageFor;
  final void Function(String key) onTap;

  const _CardChoiceRow({
    required this.keys,
    required this.selectedKey,
    required this.theme,
    required this.imageFor,
    required this.onTap,
  });

  @override
  State<_CardChoiceRow> createState() => _CardChoiceRowState();
}

// Largeur de carte (voir width: 215 plus bas) + espacement du separatorBuilder.
const double _kCardChoiceExtent = 215 + 8;

class _CardChoiceRowState extends State<_CardChoiceRow> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Météo déjà renseignée (voir MoodScreen._load) : amène directement la
    // carte déjà choisie dans le cadre visible au lieu de toujours repartir
    // du début de la rangée (voir demande utilisateur : "si j'ouvre ce soit
    // ce que j'ai sélectionné qui doit apparaître et les autres je
    // défile").
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  void _scrollToSelected() {
    if (widget.selectedKey == null || !_scrollController.hasClients) return;
    final index = widget.keys.indexOf(widget.selectedKey!);
    if (index <= 0) return;
    final offset = (index * _kCardChoiceExtent).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: widget.keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = widget.keys[i];
          final selected = widget.selectedKey == key;
          return GestureDetector(
            onTap: () => widget.onTap(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              // Largeur proche du ratio réel des images (≈ 1,5:1) — voir
              // retour utilisateur : "dézoomer" un peu, la carte trop
              // carrée par rapport à l'image forçait un recadrage serré
              // sur les côtés.
              width: 215,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected ? theme.primary : Colors.transparent, width: 3),
                boxShadow: selected
                    ? [BoxShadow(color: theme.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                // BoxFit.contain plutôt que cover (voir retour utilisateur :
                // "certaines images trop zoomées et mal représentées") — les
                // images sources n'ont pas toutes le même ratio (carrées,
                // 1.5:1...), un recadrage "cover" zoomait donc très
                // différemment selon la composition de chacune. En contain,
                // l'image entière reste toujours visible, quel que soit son
                // ratio d'origine.
                child: Container(
                  color: theme.surface,
                  child: Image.asset(widget.imageFor(key), fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

