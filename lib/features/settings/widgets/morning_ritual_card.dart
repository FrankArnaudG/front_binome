import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/box.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';
import '../../box/box_service.dart';

/// Pendant du rituel du soir (voir [EveningRitualCard]) — désactivé par
/// défaut (voir migration add_morning_ritual_to_boxes_table côté backend),
/// contrairement au soir qui l'est à la création de la Box : une nouvelle
/// notification quotidienne ne doit pas apparaître sans y avoir consenti.
class MorningRitualCard extends StatefulWidget {
  final Box box;

  const MorningRitualCard({super.key, required this.box});

  @override
  State<MorningRitualCard> createState() => _MorningRitualCardState();
}

class _MorningRitualCardState extends State<MorningRitualCard> {
  late bool _enabled;
  late TimeOfDay _time;
  bool _saving = false;
  // Tirée une fois à l'ouverture (pas à chaque rebuild) — voir les 4
  // variantes 'morning_ritual_subtitle_1'..'_4' dans translations.dart.
  late final String _subtitleKey = 'morning_ritual_subtitle_${Random().nextInt(4) + 1}';

  @override
  void initState() {
    super.initState();
    _enabled = widget.box.morningRitualEnabled;
    _time = _parseTime(widget.box.morningRitualTime);
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
  }

  String _formatTime(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _save({bool? enabled, TimeOfDay? time}) async {
    setState(() => _saving = true);
    try {
      await BoxService.instance.updateSettings(
        morningRitualEnabled: enabled ?? _enabled,
        morningRitualTime: '${_formatTime(time ?? _time)}:00',
      );
      setState(() {
        if (enabled != null) _enabled = enabled;
        if (time != null) _time = time;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) await _save(time: picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('morning_ritual_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 4),
          Text(
            t(_subtitleKey),
            style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: _saving ? null : (value) => _save(enabled: value),
            activeColor: theme.primary,
            title: Text(t('common_enabled'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
          ),
          if (_enabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.access_time_rounded, color: theme.primary),
              title: Text(t('ritual_time'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
              trailing: Text(_formatTime(_time), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.primary)),
              onTap: _saving ? null : _pickTime,
            ),
        ],
      ),
    );
  }
}
