import 'package:flutter/material.dart';

/// Pavé numérique 0-9 + retour arrière, réutilisé par tous les écrans PIN
/// (verrouillage, création, vérification).
class PinKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Color color;

  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((d) => _KeypadButton(label: d, color: color, onTap: () => onDigit(d))).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 64, height: 64),
              _KeypadButton(label: '0', color: color, onTap: () => onDigit('0')),
              _KeypadButton(icon: Icons.backspace_rounded, color: color, onTap: onBackspace),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final Color color;
  final VoidCallback onTap;

  const _KeypadButton({this.label, this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Center(
            child: label != null
                ? Text(label!, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: color))
                : Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
