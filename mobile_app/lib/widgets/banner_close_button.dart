import 'package:flutter/material.dart';

/// Chiusura senza [IconButton]: il tooltip dell'IconButton cerca un Overlay,
/// ma il banner sta sopra il Navigator e non ne ha uno. Senza overlay il
/// tooltip sostituisce il pulsante con una superficie grigia che copre la pagina.
class BannerCloseButton extends StatelessWidget {
  const BannerCloseButton({
    super.key,
    required this.onPressed,
    required this.color,
  });

  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Nascondi',
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.close, size: 18, color: color),
        ),
      ),
    );
  }
}
