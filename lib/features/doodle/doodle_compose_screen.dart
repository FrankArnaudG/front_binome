import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../models/pictionary_session.dart';
import '../games/pictionary/pictionary_canvas.dart';
import 'doodle_service.dart';

const _kDoodleColors = ['#2F6FED', '#E63E7A', '#2FBF71', '#F2A93B', '#141414'];

// Fin / moyen / épais (voir demande utilisateur, capture de référence
// montrant 3 tailles de trait) — le 4e outil de la référence (effet
// "lueur" multicolore) n'est pas repris, hors sujet ici.
const _kStrokeWidths = [3.0, 6.0, 10.0];
// Petite / moyenne / grande zone d'effacement — normalisée (même espace
// 0..1 que les points d'un trait, voir PictionaryStroke), pas en pixels :
// reste cohérente quelle que soit la taille réelle du canvas.
const _kEraserRadii = [0.02, 0.04, 0.07];

String _colorToHex(Color color) => '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Composer un doodle à envoyer au binôme (voir demande utilisateur :
/// PAS un tableau blanc collaboratif — on dessine sur SON écran, on
/// envoie, ça s'affiche en plein écran chez l'autre, voir DoodleViewScreen).
class DoodleComposeScreen extends StatefulWidget {
  const DoodleComposeScreen({super.key});

  @override
  State<DoodleComposeScreen> createState() => _DoodleComposeScreenState();
}

class _DoodleComposeScreenState extends State<DoodleComposeScreen> {
  final List<PictionaryStroke> _strokes = [];
  String _color = _kDoodleColors.first;
  double _strokeWidth = _kStrokeWidths[1];
  bool _erasing = false;
  double _eraserRadius = _kEraserRadii[1];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Masquée le temps de la composition (voir demande utilisateur :
    // "agrandir" le cadre de dessin) — même mécanisme que
    // TimelineScreen._openSend pour les écrans immersifs, remise au retour.
    AppRouter.showGlobalNavBar.value = false;
  }

  @override
  void dispose() {
    AppRouter.showGlobalNavBar.value = true;
    super.dispose();
  }

  void _onStrokeComplete(PictionaryStroke stroke) {
    setState(() => _strokes.add(stroke));
  }

  /// Retire tout trait dont au moins un point tombe dans la zone
  /// d'effacement — granularité "trait entier", pas de découpe partielle
  /// (suffisant pour un doodle léger, voir demande utilisateur : une vraie
  /// gomme au pixel près serait disproportionnée ici).
  void _onErase(Offset normalizedPoint) {
    setState(() {
      _strokes.removeWhere((stroke) => stroke.points.any((p) {
            final dx = p[0] - normalizedPoint.dx;
            final dy = p[1] - normalizedPoint.dy;
            return dx * dx + dy * dy <= _eraserRadius * _eraserRadius;
          }));
    });
  }

  void _clear() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.clear());
  }

  Future<void> _pickCustomColor() async {
    var picked = Color(int.parse(_color.replaceFirst('#', '0xFF')));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1D28),
        title: const Text('Choisis une couleur', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _color = _colorToHex(picked));
    }
  }

  Future<void> _send() async {
    if (_strokes.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await DoodleService.instance.sendDoodle(_strokes);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14131C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text('Un mot et/ou un dessin', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _strokes.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Tout effacer',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  clipBehavior: Clip.antiAlias,
                  child: PictionaryCanvas(
                    strokes: _strokes,
                    interactive: true,
                    onStrokeComplete: _onStrokeComplete,
                    strokeColor: _color,
                    strokeWidth: _strokeWidth,
                    eraseMode: _erasing,
                    eraserRadius: _eraserRadius,
                    onErase: _onErase,
                  ),
                ),
              ),
            ),
            // Pinceau / gomme (voir demande utilisateur) — la ligne de
            // tailles juste en dessous s'adapte à l'outil actif.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeTab(
                      label: 'Pinceau',
                      icon: Icons.brush_rounded,
                      selected: !_erasing,
                      onTap: () => setState(() => _erasing = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeTab(
                      label: 'Gomme',
                      icon: Icons.auto_fix_normal_rounded,
                      selected: _erasing,
                      onTap: () => setState(() => _erasing = true),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: _erasing
                    ? [
                        for (var i = 0; i < _kEraserRadii.length; i++) ...[
                          _SizeDot(
                            diameter: 14.0 + i * 8,
                            selected: _eraserRadius == _kEraserRadii[i],
                            color: Colors.white54,
                            onTap: () => setState(() => _eraserRadius = _kEraserRadii[i]),
                          ),
                          const SizedBox(width: 14),
                        ],
                      ]
                    : [
                        for (var i = 0; i < _kStrokeWidths.length; i++) ...[
                          _SizeDot(
                            diameter: 8.0 + i * 8,
                            selected: _strokeWidth == _kStrokeWidths[i],
                            color: Color(int.parse(_color.replaceFirst('#', '0xFF'))),
                            onTap: () => setState(() => _strokeWidth = _kStrokeWidths[i]),
                          ),
                          const SizedBox(width: 14),
                        ],
                      ],
              ),
            ),
            // Palette + bouton d'envoi sur la même ligne (voir demande
            // utilisateur) — le bouton reste tout à droite qu'on soit en
            // mode pinceau (couleurs affichées) ou gomme (rien à gauche).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  if (!_erasing) ...[
                    for (final hex in _kDoodleColors) ...[
                      _ColorDot(hex: hex, selected: hex == _color, onTap: () => setState(() => _color = hex)),
                      const SizedBox(width: 10),
                    ],
                    GestureDetector(
                      onTap: _pickCustomColor,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                          gradient: const SweepGradient(
                            colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red],
                          ),
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton.filled(
                    onPressed: _strokes.isEmpty ? null : _send,
                    tooltip: 'Envoyer',
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.black87 : Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.black87 : Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un choix de taille (trait ou gomme) — un simple point dont le diamètre
/// visuel reflète la taille réelle qu'il sélectionne.
class _SizeDot extends StatelessWidget {
  final double diameter;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SizeDot({required this.diameter, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
          border: selected ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({required this.hex, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(hex.replaceFirst('#', '0xFF')));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 1),
        ),
      ),
    );
  }
}
