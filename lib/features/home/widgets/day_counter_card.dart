import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/box.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_card.dart';

class DayCounterCard extends StatelessWidget {
  final Box? box;

  const DayCounterCard({super.key, required this.box});

  @override
  Widget build(BuildContext context) {
    final pairedAt = box?.pairedAt;
    final days = pairedAt != null ? DateTime.now().difference(pairedAt).inDays : null;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
            ),
            child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  days != null ? '$days jour${days > 1 ? 's' : ''} ensemble' : 'Ton histoire commence',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textOnBlush),
                ),
                const SizedBox(height: 2),
                Text(
                  days != null ? 'Depuis le jumelage 💕' : 'Le compteur démarre à ton jumelage',
                  style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textOnBlushMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
