import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/box_stats.dart';
import '../../../theme/theme_scope.dart';
import '../../box/box_service.dart';

/// "Score de complicité" ludique de l'onglet Jeux — chiffre qui monte avec
/// l'usage du couple (slides, cadeaux, cœurs battants, jours ensemble).
/// Purement informatif, aucun enjeu de classement/comparaison entre couples.
class CoupleStatsCard extends StatefulWidget {
  const CoupleStatsCard({super.key});

  @override
  State<CoupleStatsCard> createState() => _CoupleStatsCardState();
}

class _CoupleStatsCardState extends State<CoupleStatsCard> {
  BoxStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Affiche le score en cache tout de suite s'il existe (voir
  /// BoxService.cachedStats), puis rafraîchit silencieusement derrière —
  /// même principe que TimelineScreen avec ContentService.cachedSends,
  /// pour ne jamais laisser la carte vide le temps d'un aller-retour
  /// réseau à l'ouverture de l'onglet Jeux.
  Future<void> _load() async {
    final cached = await BoxService.instance.cachedStats();
    if (cached != null && mounted) setState(() => _stats = cached);

    try {
      final stats = await BoxService.instance.fetchStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // best effort — on garde le cache déjà affiché s'il y en a un,
      // sinon la carte reste simplement masquée.
    }
  }

  /// Phrase encourageante selon le pourcentage — réel et dynamique (voir
  /// EngagementScoreService côté backend, borné 2-99 %), pas une valeur
  /// figée : reflète l'engagement RÉCENT du couple, pas son ancienneté.
  String _encouragement(int percent, String Function(String, [Map<String, String>?]) t) {
    if (percent >= 80) return t('stats_tier_1');
    if (percent >= 50) return t('stats_tier_2');
    if (percent >= 20) return t('stats_tier_3');
    return t('stats_tier_4');
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final score = stats.complicityScore;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: theme.accentGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(t('stats_title'), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 6),
          if (score == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                t('stats_pending'),
                style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.92)),
              ),
            )
          else ...[
            Text(
              '$score%',
              style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              _encouragement(score, t),
              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.92)),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _StatChip(icon: Icons.auto_stories_rounded, value: stats.slidesSent, label: t('stats_slides')),
              const SizedBox(width: 10),
              _StatChip(icon: Icons.card_giftcard_rounded, value: stats.giftsSent, label: t('stats_gifts')),
              const SizedBox(width: 10),
              _StatChip(icon: Icons.favorite_border_rounded, value: stats.heartbeatsSent, label: t('stats_hearts')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _StatChip({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 4),
            Text('$value', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            Text(label, style: GoogleFonts.nunito(fontSize: 10, color: Colors.white.withValues(alpha: 0.9))),
          ],
        ),
      ),
    );
  }
}
