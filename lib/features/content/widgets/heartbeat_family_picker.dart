import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/heartbeat_family.dart';
import '../../../theme/theme_palette.dart';

/// Noms affichés sous chaque vignette — pas encore de clé de traduction
/// dédiée (voir translations.dart), ces familles ne sont montrées QUE dans
/// ce sélecteur pour l'instant.
const _heartbeatFamilyLabels = {
  'tendresse': 'Tendresse',
  'pensee': 'Pensée',
  'manque': 'Manque',
  'amour': 'Amour',
  'seduction': 'Séduction',
  'humour': 'Humour',
  'battements': 'Battements',
  'profond': 'Profond',
  'reconfort': 'Réconfort',
};

/// Sélecteur d'image de "famille" pour un battement de cœur personnalisé —
/// voir demande utilisateur : "afficher la liste des images utilisées pour
/// les familles [tirées au hasard] et le user choisira l'image à associer
/// pour envoyer le battement. juste les informations à transiter et non
/// l'image, pour ne pas dupliquer" — ne transmet QUE la clé de famille
/// choisie (voir HeartbeatController::send côté backend, qui en déduit
/// l'image packagée déjà présente dans l'app, voir heartbeatFamilies),
/// jamais un fichier ou une URL séparée. Choix optionnel : retaper sur la
/// vignette déjà sélectionnée la désélectionne (retour à la carte blanche
/// habituelle d'un message personnalisé).
class HeartbeatFamilyPicker extends StatelessWidget {
  final ThemePalette theme;
  final String? senderGender;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const HeartbeatFamilyPicker({
    super.key,
    required this.theme,
    required this.senderGender,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final keys = heartbeatFamilies.keys.toList();
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final key = keys[index];
          final style = heartbeatFamilies[key]!;
          final isSelected = selected == key;
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? theme.primary : Colors.transparent, width: 2.5),
                    image: DecorationImage(image: AssetImage(style.assetFor(senderGender)), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 60,
                  child: Text(
                    _heartbeatFamilyLabels[key] ?? key,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? theme.primary : theme.textOnBackgroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
